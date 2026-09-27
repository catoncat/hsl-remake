extends RefCounted

## Candidate-plan commander for tests/support/Autoplay.gd (`HSL_AUTOPLAY_BRAIN=scored`).
## At the first player action of every round it computes 2–9 candidate plans with numbers
## (expected damage, kills, exposure of the hero and of every other must-survive unit after the
## plan — the units the armed fail statuses name, read from the loop's own winfail rules
## (must_survive_ids), not a roster —, healing, resource cost), picks one
## by a fixed numeric score, and grounds that plan into BattlePlayLoop's public command
## entry points for each commandable unit of the round (choose_command / move_unit_to /
## attack_target / choose_magic / choose_special / use_item / finish_exhausted_action).
## Friendly AI units are not commanded. Skill numbers come from the rules' own prepare/roll
## functions (SkillResolutionRules.prepare_cast, SpecialDamageRules.roll, NativeMagicRollRules.roll,
## PoisonArrowRules.roll, SupportMagicRules.resolve) evaluated with a deterministic draw source;
## no formula is restated here. `HSL_AUTOPLAY_BRAIN=lookahead` adds the one-step lookahead:
## the same candidates plus hold_line / rescue:<pursuer> / bait:<unit>, a hard reach rule on the planned cells,
## and every admitted plan played to the end of the round on a copy of the loop
## (simulate_round) and valued by role-weighted party HP, deaths, kills, exposure and EXP
## (evaluate). This is an exploration driver for the autoplay sweep, not a product AI and not
## evidence about original balance; the default greedy policy in Autoplay.gd is untouched.

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
const ItemUse = preload("res://game/sim/ItemUseRules.gd")
const SkillResolution = preload("res://game/sim/SkillResolutionRules.gd")
const SkillTargets = preload("res://game/sim/SkillTargetRules.gd")
const SkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const SpecialDamage = preload("res://game/sim/SpecialDamageRules.gd")
const MagicRolls = preload("res://game/sim/NativeMagicRollRules.gd")
const PoisonArrow = preload("res://game/sim/PoisonArrowRules.gd")
const Support = preload("res://game/sim/SupportMagicRules.gd")
const Repeated = preload("res://game/sim/RepeatedSpecialRules.gd")
const Position = preload("res://game/sim/PositionCapabilityRules.gd")
const Progression = preload("res://game/sim/ProgressionRules.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const MODE_GREEDY := "greedy"
const MODE_SCORED := "scored"
const MODE_LOOKAHEAD := "lookahead"
const MODES := [MODE_GREEDY, MODE_SCORED, MODE_LOOKAHEAD]
## v2: magic:<skill>@<target> and special:<skill>@<target> candidates joined the plan set
## (weights WEIGHT_MP / WEIGHT_STAMINA below); v1 had advance / protect_hero / heal / focus only.
const POLICY := "candidate_plans_scored_v2_skills"
## Lookahead v1: scored's candidates + hold_line + bait, reach rule, simulated-round valuation.
const POLICY_LOOKAHEAD := "candidate_plans_lookahead_v1"
const POLICIES := {MODE_GREEDY: "greedy_public_commands_v1", MODE_SCORED: POLICY, MODE_LOOKAHEAD: POLICY_LOOKAHEAD}

## Ally HP ratio at or below which a heal candidate (item or healing skill) is offered.
const HEAL_RATIO := 0.6
## Poison (StatusEffectRules.after_action): a poisoned unit loses min(hp - 1, power) HP after
## each of its own actions until the counter runs out; it never kills alone but leaves the
## unit that low for the foes' turns (level 5: 雷歐納德 29 → 9 → 1 on two ticks of 20, then
## finished by a follow-up strike, with a 解毒草 in his pack all battle). The player sees 中毒
## (BattleVitals), not the power, so the commander prices a tick from the weapon-poison power
## domain (StatusEffectRules.WEAPON_POWER_DOMAIN): the midpoint as the expected tick, the top
## as the worst — never the unit's hidden counter.
const POISON_POWER: Array = Status.WEAPON_POWER_DOMAIN["poison"]
## Attack-cell assignment (_strike_assignment): options (cells) searched per unit.
const ASSIGNMENT_OPTIONS := 8
## At most this many focus-fire candidates (weakest strikable foes first).
const FOCUS_CANDIDATES := 3
## At most this many skill-cast candidates (best forecast value first, over every
## commandable caster, affordable skill and reachable cast).
const SKILL_CANDIDATES := 3
const MAX_CANDIDATES := 9

## Score weights (control group B: "candidates + code scoring", no model in the loop).
const WEIGHT_KILL := 25.0
const WEIGHT_HERO_DEATH := 60.0
const WEIGHT_HERO_THREAT := 8.0
## Per unit of hero_risk (expected incoming damage over current hero HP, capped at 2).
const WEIGHT_HERO_RISK := 40.0
const WEIGHT_HEAL := 0.8
const WEIGHT_HEAL_HERO_LOW := 15.0
## Per point of MP / stamina a skill cast spends: a cast must beat the weapon by this much.
const WEIGHT_MP := 0.3
const WEIGHT_STAMINA := 0.05
## Escape objective (loop objective_phase "escape" with escape_zone cells): per cell of walking
## distance (_escape_field: the movement rules' own flood over the terrain, not Manhattan —
## level 53's gate is 22 cells away as the crow flies and 54 on foot, the other way round the
## roof) the hero closes toward the nearest escape cell this round, and for standing on one
## (which decides the battle through the loop's own victory check).
const WEIGHT_ESCAPE_STEP := 6.0
const WEIGHT_ESCAPE_REACHED := 100.0
## Walking distance assigned to a cell the escape flood never reached (past every real cell).
const ESCAPE_UNREACHABLE := 10000
## Rounds without any exchange (loop last_combat unchanged) after which protect_hero /
## hold_line / bait are no longer offered: a hero hiding from a foe that never approaches
## would otherwise idle into the driver's stalemate dead_end (level 52 seed 3: emperor025
## holding at 13 cells). B1 ablation: counting a foe walking nearer as contact kept the holds
## on offer against level 2's wave but let emperor025's one-cell-a-round chase after a hero
## backing off one cell a round run into that dead_end (seed 1), so the exchange stays the
## only contact.
const IDLE_ROUNDS_BEFORE_ENGAGING := 3

## Growth points: a manual-allocation unit spends every pending point when it next acts
## (BattlePlayLoop.allocate_growth, the growth panel's own seam): GROWTH_CON_PER_LEVEL a level on
## con, the rest on its job's main attribute — the attribute with the largest per-point term in
## that job's JobStatsRules attack (or magic, for the priest / mage jobs) formula — and past its cap in GROWTH_FALLBACK
## order. Every job code not listed is "str". Automatic-allocation units grow by the rules alone.
## Before the main attribute, GROWTH_CON_PER_LEVEL of every level's ProgressionRules.POINTS_PER_LEVEL
## go to 體質 (con, the max_hp term) while its cap allows: a player keeps a point or two for HP
## (user, 2026-09-23: "机器人的加点策略应该也留最少一两点加给生命").
const GROWTH_ATTRIBUTE := {83: "dex", 84: "dex", 85: "mind", 86: "mind", 87: "mind", 90: "mind", 91: "mind"}
const GROWTH_FALLBACK := ["con", "str", "dex", "mind"]
const GROWTH_CON_PER_LEVEL := 2

## Skill damage policies the forecaster can put a number on (damage or healing). Buffs,
## dispels, steals, queue effects and pure status casts have no forecast and are not offered.
const FORECAST_POLICIES := ["native_special_damage", "native_special_sequence", "native_special_poison", "native_special_status", "native_magic_damage", "native_magic_status", "native_magic_support", "native_special_support"]

const ACTIONS := ["attack", "move_then_attack", "move", "wait", "offense_finished", "use_item", "move_then_item", "magic", "move_then_magic", "special", "move_then_special"]

## One-step lookahead (MODE_LOOKAHEAD): every candidate plan is grounded on a deep copy of
## the loop and the rest of the round (every AI turn through BattlePlayLoop.step_ai_turn,
## every later player turn grounded under the same plan) is played on the copy with every draw
## at the middle of its range (_typical_draws), then the copy's board is valued. The real loop
## is never touched: simulate_round hashes it before and after and reports a mismatch as an error.
## Rule steps one simulated round may take before it is cut off and valued where it stands.
const SIMULATION_STEP_LIMIT := 400
## Budget of one planning decision's simulations in rule steps (deterministic, unlike a wall
## clock: a run under machine load must pick the same plans): candidates are simulated in
## priority order until the simulated steps pass it (at least LOOKAHEAD_MIN_SIMULATIONS of
## them); the rest are skipped. A step is one step_ai_turn or player command (~100 ms on a
## 40-unit field, ~30 ms on a small one). A brain `deadline_msec` (the chapter suite's time
## budget) is the one wall-clock cut: past it nothing is simulated and the scored pick stands.
const LOOKAHEAD_STEP_BUDGET := 100
const LOOKAHEAD_MIN_SIMULATIONS := 2
## Hard reach rule: a plan that leaves a party unit on a cell REACH_LIMIT or more surviving
## foes can strike this round (their move + weapon reach, minus the foes the plan kills) is
## set aside; the breaching plans are simulated only when every candidate breaks the rule or
## the best admitted plan still ends in a lost battle or a hero / guarded death — valued
## (RELAX_BELOW_VALUE) or read from its own worst case (hero_can_die) — (level 28's guards
## reach the whole field and one-shot, so every "safe" hold dies in three rounds while the
## strike the rule set aside wins). A cell counts only when those foes' worst blows together
## (_worst_incoming) would kill the unit standing there: two foes that cannot kill a full-HP
## unit are the lookahead's to price (evaluate `exposure`), not a veto (R6-L3c, 40 games over
## the level 5 / 6 / 7 / 509 / 52 and memoir_05 hand-offs: 7 → 15 wins with the other R6-L3c
## plans, 6 of 40 without this clause).
const REACH_LIMIT := 2
const RELAX_BELOW_VALUE := -VALUE_GUARDED_DEATH
## Cohesion: hold_line keeps every unit within this many cells of an already placed unit.
const COHESION_DISTANCE := 2
## formation: the hero moves at most this many cells from where it stands (the block's anchor).
const FORMATION_RADIUS := 2
## Valuation weights (evaluate). Party terms are multiplied by the unit's role weight.
const VALUE_OUTCOME := 1000.0
const VALUE_GUARDED_DEATH := 500.0
const VALUE_UNIT_DEATH := 150.0
## Per full HP bar lost / dealt.
const VALUE_HP_LOST := 100.0
const VALUE_ENEMY_HP := 30.0
const VALUE_ENEMY_KILL := 40.0
## Price of the last carried healing / curing consumable the party drinks (_supplies_spent).
const VALUE_SUPPLY := 60.0
## Price of the hero's own drink from at or below LOW_HP_RATIO (_supplies_spent): half the
## VALUE_LOW_HP it lifts, so a drink that leaves him out of the low band pays for itself, and a
## round in which somebody else heals him keeps the potion (level 52, seed 1 round 13: the 024
## guest healed 雷歐納德 6 → 39 when he held; free, the drink tied with holding and took the heal).
const VALUE_LOW_HERO_DRINK := VALUE_LOW_HP / 2.0
## Rounds of a killed foe's strikes a kill is worth (_threat_removed).
const THREAT_ROUNDS := 2.0
## Per full HP bar an objective target (objective_target_ids: the foe whose fall wins the battle,
## level 6's 隊長) lost in the simulated round, on top of VALUE_ENEMY_HP: a boss outlives one
## round of focus, so without it chipping him outvalued nothing and the commander traded blows
## with the soldiers while the captain healed them (level 6, chapter hand-off).
const VALUE_OBJECTIVE_HP := 200.0
## Per step the commandable party's mean walking distance (movement cost around walls) to a
## living objective target shrank in the simulated round (_objective_distance): a player marches on the
## captain from the first round instead of waiting for him (user, level 6: "直接打队长就赢了" /
## "简单到无法理解机器人为什么会输"; the win status is armed for five rounds and the captain
## stood still behind three guards while the commander held its line, 0 of 3 seeds). The mean,
## not the nearest unit, so one unit running ahead scores little; exposure, isolation and the
## death terms still price what the march walks into.
const VALUE_OBJECTIVE_STEP := 15.0
## A marching unit (_march_step) strikes a foe on the way from a cell at most this many steps
## farther from the objective than its nearest reachable cell.
const MARCH_SLACK := 2
## Value an objective plan may trail the best simulated plan by and still be chosen
## (_march_commitment).
const MARCH_COMMITMENT := 200.0
## Per foe that can strike a living party unit where the simulated round left it, and the
## extra for standing in REACH_LIMIT or more foes' reach.
const VALUE_EXPOSURE_HP := 60.0
## A living party unit some foe can strike where the simulated round left it and with no other
## living party unit within ISOLATION_DISTANCE cells: a player keeps the party together so a
## foe that closes in meets more than one blade (level 5, chapter hand-off: 雷歐納德 fled to the
## top edge alone, 緹娜 held a cell out east alone, 琥 and 漢克斯 fought in the south — each
## was worn down by the foes that reached it, three of three seeds).
const VALUE_ISOLATED := 25.0
const ISOLATION_DISTANCE := 3
## Escort (_escort_candidate, evaluate `apart`): per cell a commandable must-survive unit other than
## the hero stands farther than ISOLATION_DISTANCE from the nearest other living party unit where
## the simulated round left it, threatened or not. A unit the fail status names that fights alone
## is worn down over rounds no single-round valuation sees (level 7, chapter hand-off: 雪拉 joins
## at round 6 in the north-east beside 036_7 / 038_5, cast from where she stood three rounds and
## fell while the party fought in the south, three of three seeds); a player walks her back to the
## party and the party toward her.
const VALUE_GUARDED_APART := 20.0
## The same gap for every other commandable party unit, times its role weight: a unit that walks
## off alone out of every foe's reach reads as safe this round and is the one the next wave
## surrounds (level 7, chapter hand-off: 漢克斯 held the south-east corner, 琥 the west edge, 緹娜
## the north while 雷歐納德 fought in the middle; each fell alone).
const VALUE_MEMBER_APART := 8.0
## A living party unit the simulated round left at or below LOW_HP_RATIO wants a heal or a
## retreat next round.
const LOW_HP_RATIO := 0.4
const VALUE_LOW_HP := 15.0
## A living party unit the simulated round left where the foes that can strike it would kill
## it if every strike landed (worst case, no hit rate) is one round from death: this share of
## the death penalties (a heal or retreat can still save it) — a single-seed simulation
## otherwise reads a 9 HP hero next to a 9-damage foe as safe (level 1: the miss that killed).
const NEXT_ROUND_DEATH_SHARE := 0.5
## Experience distribution (_level_progress): per level of progress a commandable unit makes in
## the round (the experience it gained as a share of ProgressionRules.exp_to_next at its level),
## times 1 + EXP_CATCHUP per level it stands below the party's highest member — the kill a
## level-3 緹娜 lands in a level-8 party is worth three and a half times the same share to
## 雷歐納德. A player feeds the last hits to the member who lags (encounter 509, chapter walk:
## 緹娜 entered at level 3 beside three level-8 members and fell first in every seed; the flat
## 0.05 a point this replaced priced a level of hers at a tenth of a kill).
const VALUE_LEVEL_PROGRESS := 30.0
const EXP_CATCHUP := 0.5
## Static worst case from the candidate's own numbers (hero_can_die), kept beside the
## single-seed simulation; the hero's worst case read again where the simulated round left him
## (_reach_can_die) is priced the same.
const VALUE_HERO_CAN_DIE := 60.0
## Static expectation from the candidate's own numbers (hero_expected_death: the expected
## incoming damage on a must-survive unit where the plan leaves it reaches its HP): priced
## like a worst-case death one round away (NEXT_ROUND_DEATH_SHARE of the death penalties) —
## the single-seed simulation reads a 20 HP hero left to two foes' 21.8 expected as alive
## while the real round killed him (level 3 round 3).
const VALUE_HERO_EXPECTED_DEATH := NEXT_ROUND_DEATH_SHARE * (VALUE_UNIT_DEATH + VALUE_GUARDED_DEATH)
## Escape objective: per cell of walking distance the hero closed toward the escape zone in the
## simulated round (a runner accepts some exposure; without this term every plan that keeps
## the hero out of reach outvalues running and the hero idles until the pursuers arrive).
## Only when escaping is the sole victory (loop allow_optional_clear_after_switch false): where
## the scenario also wins by clearing the field (level 51), the kill and EXP terms decide and
## the hero leaves only when the board says so — running at once forfeits the EXP the next
## battle is balanced for (chapter run: 51 won by escape at level 1, then 52 lost).
const VALUE_ESCAPE_STEP := 12.0
## Role weights: hero and guarded units 1.0 (and a hard death penalty), the party's top weapon
## damage dealer and any healer ROLE_KEY, any other skill damage dealer ROLE_CASTER, the rest
## ROLE_OTHER; friendly AI units ROLE_FRIENDLY.
const ROLE_KEY := 0.9
const ROLE_CASTER := 0.8
const ROLE_OTHER := 0.6
const ROLE_FRIENDLY := 0.35
const SUPPORT_POLICIES := ["native_magic_support", "native_special_support"]
## _threat_reach for a foe without a move_point: past every map, so the foe is always flooded.
const THREAT_REACH_UNBOUNDED := 1 << 30


## Plays `plan` for the rest of the current round on a deep copy of `loop`. Returns
## {loop, steps, msec, complete, mutated}: `loop` is the copy where the round ended (the turn
## counter advanced, a battle outcome, the event hand-off status only the scene may end
## (_event_handoff_fired), or SIMULATION_STEP_LIMIT steps / a step that made no progress —
## `complete` false for those), `mutated` true when the real loop's hash changed (a bug in a
## rule or the grounding). A fired script status does not end the round: the loop materialises
## what the status creates, retreats and waits itself (BattleLoopScript._resolve_outcome) and the
## scene only replays it, so the simulated round runs on through the firing as the real one
## does. Cutting the round there left level 6's round 2 (the round-2 dialogue event) with every
## candidate valued after the first unit's action alone — identical values for a cast on 隊長
## and a step back — and level 52 blind to the four 021s the second-to-last 021's death inserts
## beside 雷歐納德.
## The movement envelope memo is swapped out for the copy and restored afterwards.
static func simulate_round(loop: Dictionary, plan: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var before := loop.hash()
	var saved_cache := _envelope_cache
	_envelope_cache = {}
	var rng: Variant = _typical_draws()
	var sim: Dictionary = Loop.copy(loop)
	var round_number := int(sim.get("turn", 1))
	var steps := 0
	var complete := false
	while steps < SIMULATION_STEP_LIMIT:
		steps += 1
		if BattleOutcome.decided(sim) or not bool(sim.get("scenario_ok", false)) or int(sim.get("turn", 1)) != round_number:
			complete = true
			break
		if _event_handoff_fired(sim):
			complete = true
			break
		var next: Dictionary
		if Loop.loot_waiting(sim):
			# The driver's own "later" on the collection panel.
			var settlement: Dictionary = sim["settlement"]
			next = Loop.finish_rewards(sim, int(settlement["sequence"]), int(settlement["revision"]), false, true)
			if next == sim:
				break
			sim = next
			_envelope_cache.clear()
			continue
		match str(sim.get("interaction", "")):
			"action_menu":
				var id := str(sim.get("selected_unit_id", ""))
				var allocation := growth_allocation(Loop.unit(sim, id))
				if not allocation.is_empty():
					sim = Loop.allocate_growth(sim, id, allocation)
					_envelope_cache.clear()
				if Loop.action_exhausted(sim):
					next = Loop.finish_exhausted_action(sim)
				else:
					next = _ground(sim, id, plan, rng)["loop"]
			"ai_resolving":
				next = _step_ai_turn(sim, rng)
			_:
				break
		if next == sim:
			break
		sim = next
		_envelope_cache.clear()
	_envelope_cache = saved_cache
	var mutated := loop.hash() != before
	if mutated:
		push_error("AutoplayBrain.simulate_round mutated the real loop (plan %s, round %d)" % [str(plan.get("id", "")), round_number])
	return {"loop": sim, "steps": steps, "msec": float(Time.get_ticks_usec() - started) / 1000.0, "complete": complete, "mutated": mutated}


## True when the interpreter fired the event-only hand-off status of an undecided battle (the
## status the loop names next_level_event_status: WINFAIL073 / 078 / 900) — only the scene's
## cutscene path ends that battle (Autoplay._event_handoff_fired reads it the same way).
static func _event_handoff_fired(loop: Dictionary) -> bool:
	var status := str(loop.get("next_level_event_status", ""))
	if status == "" or BattleOutcome.decided(loop):
		return false
	for entry in (loop.get("winfail_runtime", {}) as Dictionary).get("fired", []):
		if str((entry as Dictionary).get("key", "")) == status:
			return true
	return false


## Rule steps of the current lookahead decision (select_lookahead opens and empties it):
## `hash(state bytes)` -> [{bytes, rng_before, loop, next, rng_after}]. BattlePlayLoop.step_ai_turn
## is a pure function of the loop and the RNG state (BattleLoopConfig: rules never write their
## input), and every candidate's simulation starts from the same loop with the same seed, so a
## candidate whose commands leave the board as an earlier one did replays that one's AI turns
## (S13: 46% of level 3's simulated AI steps repeated a state within their decision). A hit
## needs the exact state bytes (var_to_bytes of every non-CONFIG_SHARED key: type-sensitive,
## unlike ==), the same RNG state and the very same configuration blocks; it returns the
## recorded loop and moves the RNG to the recorded state after that step.
static var _ai_step_memo: Dictionary = {}
static var _ai_step_memo_open := false


static func _step_ai_turn(sim: Dictionary, rng: Variant) -> Dictionary:
	if not _ai_step_memo_open:
		return Loop.step_ai_turn(sim, rng)
	var state := {}
	for key in sim:
		if not Loop.LoopConfig.CONFIG_SHARED.has(key):
			state[key] = sim[key]
	var bytes := var_to_bytes(state)
	var digest := hash(bytes)
	# A Callable draw source (_typical_draws) carries no state: the step is a function of the loop alone.
	var stateful: bool = rng is RandomNumberGenerator
	var rng_before: int = (rng as RandomNumberGenerator).state if stateful else 0
	for entry in _ai_step_memo.get(digest, []):
		if entry["rng_before"] == rng_before and entry["bytes"] == bytes and _same_configuration(sim, entry["loop"]):
			if stateful:
				(rng as RandomNumberGenerator).state = entry["rng_after"]
			return entry["next"]
	var next := Loop.step_ai_turn(sim, rng)
	if not _ai_step_memo.has(digest):
		_ai_step_memo[digest] = []
	_ai_step_memo[digest].append({"bytes": bytes, "rng_before": rng_before, "loop": sim, "next": next, "rng_after": (rng as RandomNumberGenerator).state if stateful else 0})
	return next


## The simulated round's draw source: every draw the rules make lands at the middle of its
## range (the Callable form CoreCombatRules._rand_range and native_draw accept) — a strike whose
## hit rate is above 50 lands, a critical below a 50 chance does not, damage and AI choices take
## their middle value. A seeded generator gave one sampled future per plan: level 5 (chapter
## hand-off, seed 1, round 3) simulated 038's 27-damage blow on 緹娜 as a miss for every plan, so
## the holds that left her alone valued no death, and the real round killed her (15 + 27 on 40 HP).
static func _typical_draws() -> Callable:
	return func(bound: int) -> int:
		return bound / 2


## True when both loops hold the same CONFIG_SHARED keys, each the very same block.
static func _same_configuration(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in Loop.LoopConfig.CONFIG_SHARED:
		if left.has(key) != right.has(key) or (left.has(key) and not is_same(left[key], right[key])):
			return false
	return true


static func mode_from_environment() -> String:
	var mode := OS.get_environment("HSL_AUTOPLAY_BRAIN")
	return mode if mode in MODES else MODE_GREEDY


## Per-battle commander state; pass to Autoplay.play_battle. Empty {} means plain greedy.
static func create(mode: String) -> Dictionary:
	if mode == MODE_GREEDY:
		return {}
	return {"mode": mode, "plan": {}, "plan_round": -1, "planned_actors": [], "plans": [], "candidates_total": 0, "allocations": 0, "contact_sequence": 0, "last_contact_round": 1,
		"simulations": 0, "sim_msec": 0.0, "skipped": 0, "fallbacks": 0, "rejected": 0, "relaxed": 0, "mutations": 0, "committed": 0, "deadline_msec": 0}


## Compact per-battle statistics for the report: rounds planned, plan kinds chosen, candidates seen.
static func stats(brain: Dictionary) -> Dictionary:
	var kinds := {}
	for plan in brain.get("plans", []):
		var kind := str(plan["kind"])
		kinds[kind] = int(kinds.get(kind, 0)) + 1
	var out := {"mode": str(brain.get("mode", MODE_GREEDY)), "plans": brain.get("plans", []).size(), "plan_kinds": kinds, "candidates": int(brain.get("candidates_total", 0)), "allocations": int(brain.get("allocations", 0))}
	if str(brain.get("mode", "")) == MODE_LOOKAHEAD:
		out["lookahead"] = {"simulations": int(brain["simulations"]), "sim_msec": int(brain["sim_msec"]), "skipped": int(brain["skipped"]), "fallbacks": int(brain["fallbacks"]), "rejected": int(brain["rejected"]), "relaxed": int(brain["relaxed"]), "mutations": int(brain["mutations"]), "committed": int(brain["committed"])}
	return out


## One player action under the round's plan. Returns {loop, action}; action "" means no
## command made progress (the caller records no_legal_action). Pending growth points are
## spent first (see GROWTH_ATTRIBUTE); that keeps the actor's turn.
static func take_player_action(brain: Dictionary, loop: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	_envelope_cache.clear()
	var id := str(loop.get("selected_unit_id", ""))
	var allocation := growth_allocation(Loop.unit(loop, id))
	if not allocation.is_empty():
		var grown := Loop.allocate_growth(loop, id, allocation)
		if int(Loop.unit(grown, id).get("pending_stat_points", 0)) < int(Loop.unit(loop, id).get("pending_stat_points", 0)):
			loop = grown
			_envelope_cache.clear()
			brain["allocations"] = int(brain.get("allocations", 0)) + 1
	if Loop.action_exhausted(loop):
		return {"loop": Loop.finish_exhausted_action(loop), "action": "offense_finished"}
	loop = claim_supplies(loop)
	var round_number := int(loop.get("turn", 1))
	var is_hero := id == str(loop.get("player_unit_id", ""))
	# The speed queue interleaves foes between the round's first player action and the
	# hero's own: the hero — and every guarded unit — re-plans on its turn so its exposure
	# numbers read the foes where they stand now (level 3: planned strike cell (5,10) at
	# round start, grounded next to a foe that had since advanced, two more reached it — 3
	# of 3 runs). `planned_actors` lists the units that planned this round.
	if round_number != int(brain["plan_round"]):
		brain["planned_actors"] = []
	var guarded_actor: bool = is_hero or must_survive_ids(loop).has(id)
	if round_number != int(brain["plan_round"]) or (guarded_actor and not (brain["planned_actors"] as Array).has(id)):
		var sequence := int((loop.get("last_combat", {}) as Dictionary).get("sequence", 0))
		if sequence != int(brain["contact_sequence"]):
			brain["contact_sequence"] = sequence
			brain["last_contact_round"] = round_number
		var board := _board(loop)
		var lookahead: bool = str(brain["mode"]) == MODE_LOOKAHEAD
		_tactics = lookahead
		var options := candidates(loop, board, round_number - int(brain["last_contact_round"]), lookahead)
		brain["candidates_total"] += options.size()
		brain["plan"] = select_lookahead(brain, loop, board, options) if lookahead else select(options)
		_tactics = false
		brain["plan_round"] = round_number
		brain["planned_actors"].append(id)
		brain["plans"].append({"round": round_number, "actor": id, "id": str(brain["plan"]["id"]), "kind": str(brain["plan"]["kind"]), "score": float(brain["plan"]["score"]), "candidates": options.size()})
		if OS.get_environment("HSL_AUTOPLAY_BRAIN_TRACE") != "":
			var hero: Dictionary = board["hero"]
			print("AUTOPLAY_BRAIN round=%d actor=%s hero_hp=%d/%d pick=%s" % [round_number, id, int(hero.get("hp", 0)), int(hero.get("max_hp", 0)), str(brain["plan"]["id"])])
			var roster: Array = []
			for unit in loop.get("units", []):
				if Loop.Presence.living(unit):
					roster.append("%s:%s:%d/%d@%d,%d" % [str(unit["id"]), str(unit.get("battle_actor_role", "")).left(1), int(unit.get("hp", 0)), int(unit.get("max_hp", 0)), unit["coord"].x, unit["coord"].y])
			print("  units " + " ".join(roster))
			for candidate in options:
				var row: Dictionary = candidate.duplicate()
				row.erase("summary")
				print("  " + JSON.stringify(row))
	_tactics = str(brain["mode"]) == MODE_LOOKAHEAD
	var grounded := _ground(loop, id, brain["plan"], rng)
	_tactics = false
	return grounded


## Takes the pending loot a player would carry into the fight: every pending healing or
## poison-curing consumable (the shared pool the collection panel shows — the carry's retained
## items at the first action, drops the in-battle panel was told 「稍後」 for) goes through
## BattlePlayLoop.reopen_rewards / claim_reward into the bag of the living commandable member
## holding fewest such items (ties: roster order), and the panel is closed with 「稍後」 again
## (finish_rewards defer) so gear stays pooled as before. Returns `loop` unchanged when nothing
## usable is pending or the loop refuses. Level 5 (chapter hand-off): 漢克斯 entered with an empty
## bag while two 回復藥 and a 解毒草 sat in the pool all battle.
static func claim_supplies(loop: Dictionary) -> Dictionary:
	if _supplies(loop, loop.get("settlement", {}).get("pending", [])).is_empty():
		return loop
	var next := loop if Loop.loot_waiting(loop) else Loop.reopen_rewards(loop)
	if not Loop.loot_waiting(next):
		return loop
	var claimed := 0
	for entry in _supplies(next, next["settlement"]["pending"]):
		var best := ""
		var best_count := 0
		for id in Loop.loot_recipients(next):
			var inventory: Array = Loop.unit(next, str(id)).get("inventory", [])
			if not inventory.has(0):
				continue
			var count := _supply_count(next, inventory)
			if best == "" or count < best_count:
				best = str(id)
				best_count = count
		if best == "":
			break
		var taken := Loop.claim_reward(next, int(next["settlement"]["sequence"]), int(next["settlement"]["revision"]), str(entry["id"]), best)
		if not Loop.same_state(taken, next):
			next = taken
			claimed += 1
	var closed := Loop.finish_rewards(next, int(next["settlement"]["sequence"]), int(next["settlement"]["revision"]), false, true)
	if claimed == 0 or Loop.same_state(closed, next):
		return loop
	return closed


## Pending entries that are healing or poison-curing consumables.
static func _supplies(loop: Dictionary, pending: Array) -> Array:
	return pending.filter(func(entry): return _is_supply(loop, int(entry.get("code", 0))))


static func _is_supply(loop: Dictionary, code: int) -> bool:
	var definition: Variant = (loop.get("consumables", {}) as Dictionary).get(str(code))
	return definition is Dictionary and (int(definition.get("heal_hp", 0)) > 0 or int(definition.get("cure_poison", 0)) > 0)


static func _supply_count(loop: Dictionary, inventory: Array) -> int:
	return inventory.filter(func(code): return _is_supply(loop, int(code))).size()


## The allocation GROWTH_ATTRIBUTE prescribes for `unit`'s pending points; {} when it has
## none, is not manual-allocation, or ProgressionRules.can_allocate refuses.
static func growth_allocation(unit: Dictionary) -> Dictionary:
	var points := int(unit.get("pending_stat_points", 0))
	var growth: Dictionary = unit.get("growth_profile", {})
	if points <= 0 or str(growth.get("allocation", "")) != "manual":
		return {}
	var caps: Dictionary = growth.get("caps", {})
	var profile: Dictionary = unit.get("combat_profile", {})
	var order: Array = [GROWTH_ATTRIBUTE.get(int(growth.get("job_code", 0)), "str")]
	for key in GROWTH_FALLBACK:
		if key not in order:
			order.append(key)
	var allocation := {}
	# One con share per level the pending points stand for (a partial level counts as one).
	var levels := (points + Progression.POINTS_PER_LEVEL - 1) / Progression.POINTS_PER_LEVEL
	var con_share := mini(points, mini(GROWTH_CON_PER_LEVEL * levels, maxi(0, int(caps.get("con", 0)) - int(profile.get("con", 0)))))
	if con_share > 0:
		allocation["con"] = con_share
		points -= con_share
	for key in order:
		if points <= 0:
			break
		var spend := mini(points, maxi(0, int(caps.get(key, 0)) - int(profile.get(key, 0)) - int(allocation.get(key, 0))))
		if spend > 0:
			allocation[key] = int(allocation.get(key, 0)) + spend
			points -= spend
	return allocation if not allocation.is_empty() and Progression.can_allocate(unit, allocation) else {}


## Deterministic selection: highest score, first listed on ties.
static func select(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	for candidate in candidates:
		if best.is_empty() or float(candidate["score"]) > float(best["score"]):
			best = candidate
	return best


# ----------------------------------------------------------------------------- candidates

## 2–9 plans for this round: advance (greedy), protect_hero (unless the field has been idle
## for IDLE_ROUNDS_BEFORE_ENGAGING rounds), escape when the battle has an escape objective, heal:<ally> when a commandable
## unit holds a healing item and an ally is low (a second heal:<hero or guarded unit> when the
## lowest ally is neither: level 5, 雷歐納德 at 20/39 with 036 and 針 038 on him was offered only
## heal:緹娜 and fell that round), cure:<ally> when one holds a poison cure and an ally is poisoned, magic:<skill>@<target> / special:<skill>@<target>
## for the SKILL_CANDIDATES best forecast casts, focus:<foe> for up to FOCUS_CANDIDATES foes
## a commandable unit can strike this round (weakest first). Each plan carries the numbers
## the scorer reads. A "hold" plan (nobody moves) was dropped: protect_hero's cell search
## includes the hero's own cell and the others act greedily, so it dominated hold on every
## scored term (0 of 370 selections in the first comparison run).
static func candidates(loop: Dictionary, board: Dictionary, idle_rounds: int = 0, lookahead: bool = false) -> Array:
	var out: Array = []
	out.append(_score(_advance_candidate(loop, board)))
	if not board["hero"].is_empty() and not board["enemies"].is_empty() and idle_rounds < IDLE_ROUNDS_BEFORE_ENGAGING:
		if not lookahead or _hero_in_danger(loop, board):
			out.append(_score(_protect_candidate(loop, board)))
		if lookahead:
			out.append(_score(_hold_line_candidate(loop, board)))
			var rescue := _rescue_candidate(loop, board)
			if not rescue.is_empty():
				out.append(_score(rescue))
			for unit in _bait_units(board):
				var bait := _bait_candidate(loop, board, unit)
				if not bait.is_empty():
					out.append(_score(bait))
					break
	if lookahead and not board["enemies"].is_empty() and board["commandables"].size() > 1:
		out.append(_score(_formation_candidate(loop, board)))
	if lookahead:
		for guard_id in _apart_guards(loop, board):
			var escort := _escort_candidate(loop, board, Loop.unit(loop, str(guard_id)))
			if not escort.is_empty():
				out.append(_score(escort))
	var heal := _heal_candidate(loop, board)
	var heals: Array = [] if heal.is_empty() else [heal]
	if not heal.is_empty() and not bool(heal["heal_target_protected"]):
		var guard_heal := _heal_candidate(loop, board, true)
		if not guard_heal.is_empty():
			heals.append(guard_heal)
	for index in range(heals.size()):
		out.append(_score(heals[index]))
		var held := _hold_drink_candidate(loop, board, heals[index], index > 0) if lookahead else {}
		if not held.is_empty():
			out.append(_score(held))
	var cure := _cure_candidate(loop, board)
	if not cure.is_empty():
		out.append(_score(cure))
	var escape := _escape_candidate(loop, board)
	if not escape.is_empty():
		out.append(_score(escape))
	for intent in _skill_picks(loop, board):
		out.append(_score(_skill_candidate(loop, board, intent)))
	for foe_id in board["objectives"]:
		var target := Loop.unit(loop, str(foe_id))
		out.append(_score(_objective_candidate(loop, board, target)))
	for foe in _focus_targets(loop, board):
		if out.size() >= MAX_CANDIDATES:
			break
		if not board["objectives"].has(str(foe["id"])):
			out.append(_score(_focus_candidate(loop, board, foe)))
	return out


## True when the hero stands at or below HEAL_RATIO or where the foes that reach it would kill it
## (_in_kill_range): the lookahead offers protect_hero only then.
static func _hero_in_danger(loop: Dictionary, board: Dictionary) -> bool:
	var hero: Dictionary = board["hero"]
	if float(hero.get("hp", 0)) / maxf(1.0, float(hero.get("max_hp", 1))) <= HEAL_RATIO:
		return true
	return _in_kill_range(loop, board, hero, _pending_ids(loop))


## The SKILL_CANDIDATES best forecast casts, and always the best healing cast on the hero or a
## guarded unit when one exists (in place of the last damage cast): a 70-damage special
## outranks a 22-point heal on forecast value, so a hero at 3 HP saw three damage casts and no
## heal (level 2 round 16, the 023 wave). A healing forecast is non-zero only for a target at
## or below HEAL_RATIO (_forecast_cast).
static func _skill_picks(loop: Dictionary, board: Dictionary) -> Array:
	var intents := _skill_intents(loop, board)
	var picked: Array = intents.slice(0, SKILL_CANDIDATES)
	var protected: Array = board["guarded"].duplicate()
	if not board["hero"].is_empty():
		protected.append(str(board["hero"]["id"]))
	for intent in intents:
		if int(intent["heal_hp"]) <= 0 or not protected.has(str(intent["target_id"])):
			continue
		if not picked.has(intent):
			if picked.size() >= SKILL_CANDIDATES:
				picked[picked.size() - 1] = intent
			else:
				picked.append(intent)
		break
	for intent in intents:
		if float(intent["expected_damage"]) <= 0.0 or not board["objectives"].has(str(intent["target_id"])):
			continue
		if not picked.has(intent):
			picked.append(intent)
		break
	return picked


static func _score(candidate: Dictionary) -> Dictionary:
	var score := float(candidate["expected_damage"]) + WEIGHT_KILL * float(candidate["kills"])
	score -= WEIGHT_HERO_DEATH * (1.0 if bool(candidate["hero_can_die"]) else 0.0)
	score -= WEIGHT_HERO_THREAT * float(candidate["hero_threat_after"]) + WEIGHT_HERO_RISK * float(candidate["hero_risk"])
	score += WEIGHT_HEAL * float(candidate.get("heal_hp", 0))
	if bool(candidate.get("heal_target_is_hero", false)) and float(candidate.get("heal_target_hp_ratio", 1.0)) < 0.5:
		score += WEIGHT_HEAL_HERO_LOW
	score -= _cost_penalty(str(candidate.get("resource", "")), int(candidate.get("cost", 0)))
	if candidate.has("escape_distance_after"):
		score += WEIGHT_ESCAPE_STEP * float(int(candidate["escape_distance_before"]) - int(candidate["escape_distance_after"]))
		score += WEIGHT_ESCAPE_REACHED * (1.0 if bool(candidate["escape_reached"]) else 0.0)
	candidate["score"] = snappedf(score, 0.01)
	return candidate


static func _cost_penalty(resource: String, cost: int) -> float:
	return (WEIGHT_MP if resource == "mp" else WEIGHT_STAMINA) * float(cost)


## Shared round facts: hero, commandable units, living foes, and every foe's threat cells
## (cells its weapon touches from any cell it can reach this round, the movement rules' own
## flood over every body where it stands). Known bias, kept: a party body that acts before
## the foe does not really shield (level 3 round 5: 琥, speed 17, standing in the one open
## column read as blocking two speed-16 028s' path to 緹娜, moved first in round 6 and both
## walked through and killed her); flooding without the faster party bodies was tried (B1
## ablation) and lost level 3 in this seed while flooding without any party body lost level
## 53's corridor run, so the shared map keeps every body and the must-survive pricing below
## carries the protection instead.
## The threat map is filled per queried cell (_threat_at): `threat_foes` lists every foe that
## can strike, in `enemies` order, with its reach bound, and a foe is flooded only when a
## queried cell lies within that bound (S13: a level-44 decision flooded all 73 foes on each
## of its 22 boards; the party's cells are near a handful of them).
static func _board(loop: Dictionary) -> Dictionary:
	var hero := Loop.unit(loop, str(loop.get("player_unit_id", "")))
	if not Loop.Presence.living(hero):
		hero = {}
	var commandables: Array = []
	var enemies: Array = []
	for unit in loop.get("units", []):
		if not Loop.Presence.living(unit):
			continue
		var role := str(unit.get("battle_actor_role", ""))
		if role == Loop.ROLE_ENEMY:
			enemies.append(unit)
		elif role == Loop.ROLE_PLAYER and bool(unit.get("player_commandable", false)):
			commandables.append(unit)
	var threat_foes: Array = []
	for foe in enemies:
		if bool(foe.get("no_attack", false)):
			continue
		var pattern := Loop.weapon_pattern(loop, foe)
		if not bool(pattern.get("ok", false)):
			continue
		threat_foes.append({"id": str(foe["id"]), "coord": foe["coord"], "offsets": pattern["offsets"], "reach": _threat_reach(foe, pattern["offsets"])})
	# Party-side must-survive units beside the hero (a commandable or a friendly AI unit such
	# as level 17's escort): their exposure and death are priced like the hero's.
	var guarded: Array = []
	for id in must_survive_ids(loop):
		var unit := Loop.unit(loop, str(id))
		if Loop.Presence.living(unit) and str(id) != str(hero.get("id", "")) and str(unit.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]:
			guarded.append(str(id))
	return {"hero": hero, "commandables": commandables, "enemies": enemies, "threat": {}, "threat_foes": threat_foes, "guarded": guarded, "objectives": objective_target_ids(loop), "actor_id": str(loop.get("selected_unit_id", ""))}


## Manhattan bound on the cells `foe`'s weapon can touch this round, from where it stands:
## its move points (a flood step costs at least 1 — ActorTraversalRules.tile_error refuses a
## move_cost below 1 and a refused map floods nothing) plus the longest weapon offset.
## Without a move_point field the flood's own read fails; no bound is claimed then.
static func _threat_reach(foe: Dictionary, offsets: Array) -> int:
	if not foe.has("move_point"):
		return THREAT_REACH_UNBOUNDED
	var longest := 0
	for offset in offsets:
		longest = maxi(longest, absi(int(offset[0])) + absi(int(offset[1])))
	return maxi(0, int(foe["move_point"])) + longest


## Foe ids whose weapon touches `point` this round (the eager threat map's cell list, in
## `enemies` order), memoized in board["threat"]. A foe's touched cells are built on first need
## from its memoized movement envelope (_movement_cells: the same loop, so the query must come
## while the envelope memo belongs to that loop — as every board query already does).
static func _threat_at(loop: Dictionary, board: Dictionary, point: Vector2i) -> Array:
	var threat: Dictionary = board["threat"]
	if threat.has(point):
		return threat[point]
	var ids: Array = []
	for entry in board["threat_foes"]:
		var coord: Vector2i = entry["coord"]
		if absi(point.x - coord.x) + absi(point.y - coord.y) > int(entry["reach"]):
			continue
		if not entry.has("touched"):
			var origins: Array = _movement_cells(loop, str(entry["id"])).duplicate()
			origins.append(coord)
			var touched := {}
			for origin in origins:
				for cell in Loop.TacticalGridRules.attack_pattern_cells(origin, entry["offsets"], loop["map_size"]):
					touched[cell] = true
			entry["touched"] = touched
		if (entry["touched"] as Dictionary).has(point):
			ids.append(entry["id"])
	threat[point] = ids
	return ids


## The briefing's must-survive set: units whose fall alone would fire an armed fail status
## right now. Every armed fail status (loop fail_statuses) is read for its actCheckPlayer /
## actCheckEnemy conditions — `[num][id1][id2]…` fires when `num` of the listed tokens have no
## unit left on the field (WinfailConditions.condition_holds) — and when one more fallen token
## fires it, every living unit that is the last of its token is must-survive. Tokens resolve
## through WinfailConditions' own resolution (opening bindings `SID_緹娜/1`, classes
## `SID_ENEMY064`, `SID_PLAYERn`), the same the interpreter reads; unresolved and never-fielded
## tokens do not count there either. Level 3: 雷歐納德 and 緹娜 (two `1 <token>` statuses);
## level 1's `2 SID_ENEMY061 SID_ENEMY062`: nobody until one villager class is wiped, then the
## last villager of the other. Nothing here is a hard-coded roster.
static func must_survive_ids(loop: Dictionary) -> Array:
	return _last_of_tokens(loop, "fail", loop.get("fail_statuses", []))


## The briefing's objective: living foes whose fall alone would fire an armed win status right
## now — the 打倒隊長 the victory panel names — read the way must_survive_ids reads the fail
## statuses (loop win_statuses, actCheckEnemy / actCheckPlayer conditions, the last unit of a
## token one fall short of firing). Level 6: guard024_1 (`actCheckEnemy,1,SID_ENEMY024`); a
## clear-the-field status (actCheckEnemyTotalNumber) names nobody. Nothing is a roster.
static func objective_target_ids(loop: Dictionary) -> Array:
	return _last_of_tokens(loop, "win", loop.get("win_statuses", [])).filter(func(id):
		var unit := Loop.unit(loop, str(id))
		return Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) == Loop.ROLE_ENEMY)


## Units whose fall alone fires one of the `armed` statuses of `section` ("win" / "fail").
static func _last_of_tokens(loop: Dictionary, section: String, armed: Array) -> Array:
	var rules: Dictionary = loop.get("winfail_script_rules", {})
	var ids := {}
	for status in (rules.get("statuses", {}) as Dictionary).get(section, []):
		if armed.find(int(status.get("code", -1))) == -1:
			continue
		for condition in status.get("conditions", []):
			if str(condition.get("name", "")) not in ["actCheckPlayer", "actCheckEnemy"]:
				continue
			var args: Array = condition.get("args", [])
			if args.size() < 2:
				continue
			var needed := mini(int(str(args[0])), args.size() - 1)
			var fallen := 0
			var standing: Array = []
			for index in range(1, args.size()):
				var token := str(args[index])
				var source := WinfailConditions.token_source(loop, token)
				if source == "unresolved" or (source == "binding" and WinfailConditions.units_for_token(loop, token).is_empty()):
					continue
				var alive := WinfailConditions.alive_units_for_token(loop, token)
				if alive.is_empty():
					fallen += 1
				else:
					standing.append(alive)
			if needed <= 0 or needed - fallen != 1:
				continue
			for alive in standing:
				if alive.size() == 1:
					ids[str(alive[0])] = true
	return ids.keys()


## Where a guarded unit (a non-hero unit an armed fail status names) really goes: `cell` unless
## every threatening foe landing its preview damage there would kill it and its least-threatened
## reachable cell is safer — then that cell (striking from there when anything is in range).
## The hero follows its scored plan instead; its exposure is priced by the candidates.
static func _guarded_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, cell: Vector2i) -> Vector2i:
	if not board["guarded"].has(str(unit["id"])):
		return cell
	var hp := int(unit.get("hp", 0))
	var worst := _worst_incoming(loop, unit, _threatening(loop, board, unit, cell))
	if worst < hp:
		return cell
	var safe := _safest_cell(loop, board, unit)
	return safe if _worst_incoming(loop, unit, _threatening(loop, board, unit, safe)) < worst else cell


## Foes that threaten `unit` standing at `origin`: distinct ids over its footprint cells.
static func _threatening(loop: Dictionary, board: Dictionary, unit: Dictionary, origin: Vector2i) -> Array:
	var ids := {}
	for point in Loop.Footprint.cells(unit, origin):
		for id in _threat_at(loop, board, point):
			ids[id] = true
	return ids.keys()


## Expected damage the listed foes deal to `unit` (deterministic preview × hit rate).
static func _expected_incoming(loop: Dictionary, unit: Dictionary, foe_ids: Array) -> float:
	var total := 0.0
	for id in foe_ids:
		var foe := Loop.unit(loop, str(id))
		if foe.is_empty():
			continue
		total += _expected_strike(foe, unit)
	return total


static func _expected_strike(attacker: Dictionary, defender: Dictionary) -> float:
	var preview := Combat.preview_attack(attacker, defender, null)
	return float(preview["damage"]) * float(preview["hit_rate"]) / 100.0


## Damage the listed foes deal to `unit` if every strike lands (deterministic preview, no hit
## rate); with `critical`, one of them — the one it hurts most from — is a critical
## (CoreCombatRules.critical_impact at its midpoint draw, for a foe whose 暴擊 rate is above 0):
## a 28 HP hero read as safe against a 13-damage foe fell to its 29-damage critical (level 3
## round 3). Only the candidates' own hero_can_die and the hero's re-read of it on the
## simulated board (_reach_can_die) read the critical case; the simulated board's next-round
## check of every party unit, the bait survival test and the guarded grounding keep the plain
## worst case (B1 ablation: the critical case everywhere made level 2's party too slow to
## clear the road before the round-11 wave and lost it).
static func _worst_incoming(loop: Dictionary, unit: Dictionary, foe_ids: Array, critical: bool = false) -> int:
	var total := 0
	var critical_extra := 0
	for id in foe_ids:
		var foe := Loop.unit(loop, str(id))
		if foe.is_empty():
			continue
		var damage := int(Combat.preview_attack(foe, unit, null)["damage"])
		total += damage
		var chance := int(Combat.combat_profile_from_unit(foe).get("attack_damagex2", 0))
		if critical and chance > 0:
			# The rules' own critical formula forced to fire (chance 100 against the midpoint roll).
			critical_extra = maxi(critical_extra, int(Combat.critical_impact(damage, true, 100, null)["damage"]) - damage)
	return total + critical_extra


## Hero exposure numbers for a plan whose hero ends the round at `hero_cell`. hero_can_die
## reads the worst case (every threatening foe lands its preview damage), not the expectation:
## a 30 HP hero two 15-damage foes can reach died on the expectation in 3 of 3 level-2 runs.
## `strike_foe_id` / `strike_kills` name the hero's own weapon strike this round: a surviving
## foe whose weapon reaches the hero's cell counters (CoreCombatRules.attack_back_triggered
## chance, counter damage 80%), which the threat map — foes' own turns — does not contain.
## Every other must-survive unit (board.guarded) is priced the same way where the plan leaves
## it: `actor_cell` / `actor_strike` (its own cell and weapon strike) when it is the acting
## unit, else its planned cell in `cells` while it is still to act this round, else where it
## stands (a unit that has acted, or a friendly AI escort, does not move on the plan's word).
## Their risks add to hero_risk, their worst cases join hero_can_die (`guarded_cells`,
## `guarded_threat_after`, `guarded_risk` in the candidate).
## Foes the plan expects to kill (`kill_ids`) threaten nobody afterwards (level 3 round 4: the
## one 036 next to a 24 HP hero read as a death risk on every cell from which the hero and 琥
## would kill it, so the hero ran instead and was chased down).
## A poisoned must-survive unit still to act this round meets the foes' turns after its own
## poison tick (_poison_tick), unless the plan cures it (`cured_ids`): its HP for the risk and
## expected-death numbers loses the expected tick, for hero_can_die the worst tick.
static func _hero_numbers(loop: Dictionary, board: Dictionary, hero_cell: Variant, strike_foe_id: String = "", strike_kills: bool = false, actor_cell: Variant = null, actor_strike: Dictionary = {}, cells: Dictionary = {}, kill_ids: Array = [], cured_ids: Array = []) -> Dictionary:
	var hero: Dictionary = board["hero"]
	var out := {"hero_cell": null, "hero_threat_after": 0, "hero_expected_incoming_after": 0.0, "hero_risk": 0.0, "hero_can_die": false, "hero_expected_death": false, "hero_counter_after": 0.0}
	var pending := _pending_ids(loop)
	if not hero.is_empty() and hero_cell is Vector2i:
		var ids := _threatening(loop, board, hero, hero_cell).filter(func(id): return not kill_ids.has(str(id)))
		var counter := _counter_numbers(loop, hero, hero_cell, strike_foe_id, strike_kills)
		var incoming := _expected_incoming(loop, hero, ids) + float(counter["expected"])
		var hp := maxf(1.0, float(int(hero.get("hp", 0)) - _poison_tick(hero, pending, cured_ids, false)))
		var hp_worst := maxi(1, int(hero.get("hp", 0)) - _poison_tick(hero, pending, cured_ids, true))
		out = {"hero_cell": [hero_cell.x, hero_cell.y], "hero_threat_after": ids.size(), "hero_expected_incoming_after": snappedf(incoming, 0.1), "hero_risk": snappedf(minf(incoming / hp, 2.0), 0.01), "hero_can_die": _worst_incoming(loop, hero, ids, true) + int(counter["worst"]) >= hp_worst, "hero_expected_death": incoming >= hp, "hero_counter_after": snappedf(float(counter["expected"]), 0.1)}
	if (board["guarded"] as Array).is_empty():
		return out
	var actor_id := str(board.get("actor_id", ""))
	var guarded_cells := {}
	var guarded_threats := 0
	var guarded_risk := 0.0
	var guarded_can_die := false
	var guarded_expected_death := false
	for id in board["guarded"]:
		var unit := Loop.unit(loop, str(id))
		if unit.is_empty():
			continue
		var cell: Vector2i = unit["coord"]
		var strike := {}
		if str(id) == actor_id and actor_cell is Vector2i:
			cell = actor_cell
			strike = actor_strike
		elif pending.has(str(id)) and cells.get(str(id)) is Vector2i:
			cell = cells[str(id)]
		var ids := _threatening(loop, board, unit, cell).filter(func(id): return not kill_ids.has(str(id)))
		var counter := _counter_numbers(loop, unit, cell, str(strike.get("foe_id", "")), int(strike.get("kills", 0)) > 0)
		var incoming := _expected_incoming(loop, unit, ids) + float(counter["expected"])
		var hp := maxf(1.0, float(int(unit.get("hp", 0)) - _poison_tick(unit, pending, cured_ids, false)))
		var hp_worst := maxi(1, int(unit.get("hp", 0)) - _poison_tick(unit, pending, cured_ids, true))
		guarded_cells[str(id)] = [cell.x, cell.y]
		guarded_threats += ids.size()
		guarded_risk += minf(incoming / hp, 2.0)
		guarded_can_die = guarded_can_die or _worst_incoming(loop, unit, ids, true) + int(counter["worst"]) >= hp_worst
		guarded_expected_death = guarded_expected_death or incoming >= hp
	out["guarded_cells"] = guarded_cells
	out["guarded_threat_after"] = guarded_threats
	out["guarded_risk"] = snappedf(guarded_risk, 0.01)
	out["hero_risk"] = snappedf(float(out["hero_risk"]) + guarded_risk, 0.01)
	out["hero_can_die"] = bool(out["hero_can_die"]) or guarded_can_die
	out["hero_expected_death"] = bool(out["hero_expected_death"]) or guarded_expected_death
	return out


## Units still to act this round: the speed queue's slots from the current one on (the walk
## CoreTurnQueue.current makes); [] without a queue.
static func _pending_ids(loop: Dictionary) -> Array:
	var queue: Dictionary = loop.get("turn_queue", {})
	var slots: Array = queue.get("slots", [])
	var out: Array = []
	for index in range(maxi(0, int(queue.get("index", 0))), slots.size()):
		var slot: Dictionary = slots[index]
		if bool(slot.get("enabled", true)) and not bool(slot.get("consumed", false)) and str(slot.get("id", "")) != "":
			out.append(str(slot["id"]))
	return out


## HP a poisoned `unit` loses to its own poison tick before the foes' turns this round: the
## expected (POISON_POWER midpoint) or `worst` (its top) tick, capped at hp - 1 like
## StatusEffectRules.after_action; 0 when it is not poisoned (the 中毒 flag the player sees),
## the plan cures it (`cured_ids`) or it has already acted this round (not in `pending`).
static func _poison_tick(unit: Dictionary, pending: Array, cured_ids: Array, worst: bool) -> int:
	var id := str(unit.get("id", ""))
	if (int(unit.get("status_flags", 0)) & Status.POISON) == 0 or cured_ids.has(id) or not pending.has(id):
		return 0
	return _poison_tick_hp(unit, worst)


## One poison tick on `unit` at its current HP (POISON_POWER, capped at hp - 1), whenever it acts.
static func _poison_tick_hp(unit: Dictionary, worst: bool) -> int:
	var power := int(POISON_POWER[1]) if worst else (int(POISON_POWER[0]) + int(POISON_POWER[1])) / 2
	return clampi(int(unit.get("hp", 0)) - 1, 0, power)


## {expected, worst} counter damage the hero draws by striking `foe_id` from `hero_cell` and
## leaving it alive; 0 when no strike, the foe dies, or its weapon does not reach the cell.
static func _counter_numbers(loop: Dictionary, hero: Dictionary, hero_cell: Vector2i, foe_id: String, kills: bool) -> Dictionary:
	var none := {"expected": 0.0, "worst": 0}
	if foe_id == "" or kills:
		return none
	var foe := Loop.unit(loop, foe_id)
	if not Loop.Presence.living(foe) or bool(foe.get("no_attack", false)):
		return none
	var pattern := Loop.weapon_pattern(loop, foe)
	if not bool(pattern.get("ok", false)):
		return none
	var reach: Array = Loop.TacticalGridRules.attack_pattern_cells(foe["coord"], pattern["offsets"], loop["map_size"])
	if not Loop.Footprint.overlaps(hero, reach, hero_cell):
		return none
	var chance := clampi(int(Combat.combat_profile_from_unit(foe).get("attack_back", 0)), 0, 100)
	var preview := Combat.preview_attack(foe, hero, null)
	var worst := maxi(1, int(preview["damage"]) * 80 / 100)
	return {"expected": float(worst) * float(preview["hit_rate"]) / 100.0 * float(chance) / 100.0, "worst": worst if chance > 0 else 0}


## `cells` (unit id -> planned Vector2i) and `kill_ids` (foes the plan expects to kill) feed
## the lookahead's reach rule and the hold_line / bait grounding; cells are stored as [x, y].
static func _candidate(id: String, kind: String, summary: String, expected_damage: float, kills: int, hero: Dictionary, cells: Dictionary = {}, kill_ids: Array = []) -> Dictionary:
	var out := {"id": id, "kind": kind, "summary": summary, "expected_damage": snappedf(expected_damage, 0.1), "kills": kills}
	out.merge(hero, true)
	var planned := {}
	for unit_id in cells:
		var cell: Vector2i = cells[unit_id]
		planned[str(unit_id)] = [cell.x, cell.y]
	out["cells"] = planned
	out["kill_ids"] = kill_ids.duplicate()
	return out


static func _record_step(cells: Dictionary, kill_ids: Array, unit_id: String, step: Dictionary) -> void:
	if step.get("cell") is Vector2i:
		cells[unit_id] = step["cell"]
	if int(step.get("kills", 0)) > 0 and str(step.get("foe_id", "")) != "" and not kill_ids.has(str(step["foe_id"])):
		kill_ids.append(str(step["foe_id"]))


static func _planned_cell(plan: Dictionary, unit_id: String) -> Variant:
	var cells: Dictionary = plan.get("cells", {})
	if not cells.has(unit_id):
		return null
	var cell: Array = cells[unit_id]
	return Vector2i(int(cell[0]), int(cell[1]))


## Greedy for everyone: strike the weakest reachable foe, else approach the nearest.
static func _advance_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var damage := 0.0
	var kills := 0
	var hero_cell: Variant = null
	var hero_step := {}
	var actor_step := {}
	var cells := {}
	var kill_ids: Array = []
	for unit in board["commandables"]:
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["hero"].get("id", "")):
			hero_cell = step["cell"]
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	return _candidate("advance", "advance", "Every commandable unit strikes the weakest foe it can reach, else moves toward the nearest foe.", damage, kills, _hero_numbers(loop, board, hero_cell, str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)


## The hero retreats like protect_hero (_safest_cell, striking from there when a foe is in
## range) while every other commandable unit turns on its pursuer — the foe threatening the
## hero where it stands that would hit it hardest: those that can strike it from a cell fewer
## than REACH_LIMIT other foes reach do, the rest close in on it. Level 5 (chapter hand-off):
## protect_hero alone let a 72 HP 036 walk 雷歐納德 along the top edge for four rounds while
## the others chased the weakest foes elsewhere. {} when nothing threatens the hero's cell or
## the hero is the only commandable unit.
static func _rescue_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var hero: Dictionary = board["hero"]
	if hero.is_empty() or board["commandables"].size() < 2:
		return {}
	var pursuer := {}
	var hardest := -1.0
	for foe_id in _threatening(loop, board, hero, hero["coord"]):
		var foe := Loop.unit(loop, str(foe_id))
		var strike := _expected_strike(foe, hero)
		if strike > hardest or (strike == hardest and int(foe["hp"]) < int(pursuer["hp"])):
			pursuer = foe
			hardest = strike
	if pursuer.is_empty():
		return {}
	var safe := _safest_cell(loop, board, hero)
	var hero_strike := _best_strike_from(loop, hero, safe)
	var damage := float(hero_strike.get("expected_damage", 0.0))
	var on_pursuer := str(hero_strike.get("foe_id", "")) == str(pursuer["id"])
	var pursuer_damage := float(hero_strike.get("expected_damage", 0.0)) if on_pursuer else 0.0
	var kills := 0 if on_pursuer else int(hero_strike.get("kills", 0))
	var actor_step := {}
	var cells := {str(hero["id"]): safe}
	var kill_ids: Array = []
	if not on_pursuer and int(hero_strike.get("kills", 0)) > 0:
		kill_ids.append(str(hero_strike["foe_id"]))
	for unit in board["commandables"]:
		if str(unit["id"]) == str(hero["id"]):
			continue
		var cell: Variant = _focus_cell(loop, board, unit, pursuer)
		if cell is Vector2i and _exposed(loop, board, unit, cell, str(pursuer["id"])):
			cell = null
		var step := {}
		if cell is Vector2i:
			var expected := _expected_strike(unit, pursuer)
			pursuer_damage += expected
			damage += expected
			cells[str(unit["id"])] = cell
			step = {"cell": cell, "foe_id": str(pursuer["id"]), "kills": 0}
		else:
			step = _greedy_intent(loop, board, unit, true, pursuer)
			damage += float(step["expected_damage"])
			kills += int(step["kills"])
			_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	var pursuer_dies := pursuer_damage >= float(pursuer["hp"])
	if pursuer_dies:
		kills += 1
		kill_ids.append(str(pursuer["id"]))
		if str(actor_step.get("foe_id", "")) == str(pursuer["id"]):
			actor_step["kills"] = 1
	var out := _candidate("rescue:%s" % str(pursuer["id"]), "rescue", "The hero retreats to its safest cell; the others turn on %s (hp %d/%d), the foe threatening the hero hardest." % [str(pursuer["id"]), int(pursuer["hp"]), int(pursuer["max_hp"])], damage, kills, _hero_numbers(loop, board, safe, str(hero_strike.get("foe_id", "")), int(hero_strike.get("kills", 0)) > 0 or (on_pursuer and pursuer_dies), actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	out["target_id"] = str(pursuer["id"])
	return out


## Hero retreats to its least-threatened reachable cell (strikes from there if any foe is in
## range); other commandable units act greedily.
static func _protect_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var hero: Dictionary = board["hero"]
	var damage := 0.0
	var kills := 0
	var safe := _safest_cell(loop, board, hero)
	var hero_strike := _best_strike_from(loop, hero, safe)
	damage += float(hero_strike.get("expected_damage", 0.0))
	kills += int(hero_strike.get("kills", 0))
	var actor_step := {}
	var cells := {}
	var kill_ids: Array = []
	hero_strike["cell"] = safe
	_record_step(cells, kill_ids, str(hero["id"]), hero_strike)
	for unit in board["commandables"]:
		if str(unit["id"]) == str(hero["id"]):
			continue
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	return _candidate("protect_hero", "protect_hero", "The hero moves to the reachable cell fewest foes can strike this round; others act greedily.", damage, kills, _hero_numbers(loop, board, safe, str(hero_strike.get("foe_id", "")), int(hero_strike.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)


## Heal the lowest-HP player-side unit a commandable unit with a healing item can reach.
## {} when no commandable unit holds a healing item or nobody is at or below HEAL_RATIO.
## The hero's exposure is read where the plan leaves it: its heal cell as the healer, else its
## greedy step like every other plan's (level 3 round 5: read at its current cell among three
## foes, the heal 緹娜 needed scored as the hero's death).
static func _heal_candidate(loop: Dictionary, board: Dictionary, protected_only: bool = false, drink_cell: Variant = null) -> Dictionary:
	var plan := _heal_intent(loop, board, protected_only)
	if plan.is_empty():
		return {}
	if drink_cell is Vector2i:
		plan["cell"] = drink_cell
	var hero: Dictionary = board["hero"]
	var target := Loop.unit(loop, str(plan["target_id"]))
	var hero_cell: Variant = null
	var hero_step := {}
	if not hero.is_empty() and str(plan["healer_id"]) == str(hero["id"]):
		hero_cell = plan["cell"]
	var damage := 0.0
	var kills := 0
	var actor_step := {"cell": plan["cell"]} if str(plan["healer_id"]) == str(board["actor_id"]) else {}
	var cells := {str(plan["healer_id"]): plan["cell"]}
	var kill_ids: Array = []
	for unit in board["commandables"]:
		if str(unit["id"]) == str(plan["healer_id"]):
			continue
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(hero.get("id", "")):
			hero_cell = step["cell"]
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	# The exposure numbers read the healed target at its HP after the drink: a heal on the hero
	# priced at the HP it is about to leave read every heal as dangerous as standing still
	# (level 52, seed 5 round 6: heal:leonard at 16/35 carried hero_can_die like the kill beside
	# it, and the next 021 struck him dead for 16).
	var numbers_loop := loop
	var numbers_board := board
	if str(plan["target_id"]) == str(hero.get("id", "")) or board["guarded"].has(str(plan["target_id"])):
		numbers_loop = Loop.copy(loop)
		for unit in numbers_loop["units"]:
			if str(unit["id"]) == str(plan["target_id"]):
				unit["hp"] = mini(int(unit["max_hp"]), int(unit["hp"]) + int(plan["heal_hp"]))
		numbers_board = board.duplicate()
		if not hero.is_empty():
			numbers_board["hero"] = Loop.unit(numbers_loop, str(hero["id"]))
	var out := _candidate("heal:%s" % str(plan["target_id"]), "heal", "%s uses a healing item on %s (hp %d/%d); others act greedily." % [str(plan["healer_id"]), str(plan["target_id"]), int(target["hp"]), int(target["max_hp"])], damage, kills, _hero_numbers(numbers_loop, numbers_board, hero_cell, str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	out["heal_hp"] = int(plan["heal_hp"])
	out["heal_target_hp_ratio"] = snappedf(float(target["hp"]) / maxf(1.0, float(target["max_hp"])), 0.01)
	out["heal_target_is_hero"] = str(plan["target_id"]) == str(hero.get("id", ""))
	out["heal_target_protected"] = out["heal_target_is_hero"] or board["guarded"].has(str(plan["target_id"]))
	out["healer_id"] = str(plan["healer_id"])
	out["target_id"] = str(plan["target_id"])
	out["item_code"] = str(plan["item_code"])
	if drink_cell is Vector2i:
		out["id"] = "%s@hold" % str(out["id"])
		out["heal_cell"] = drink_cell
	return out


## The lookahead's second heal plan for the hero drinking on himself: the same drink from his
## hold_line cell (_hold_cell: out of every foe's reach, as near the foes as that allows), {}
## when the heal plan is another or already stands there. The heal plan's own cell is the
## nearest least-threatened one (_adjacent_cell), which walks a lone hero away from the line
## and the guest beside it: level 52, seed 1 round 16, 雷歐納德 at 11/39 — the drink at (9,33)
## read isolated, apart and a step back (-63 before its price) while holding at (11,29) read +15
## march, so he held at 11 HP.
static func _hold_drink_candidate(loop: Dictionary, board: Dictionary, heal: Dictionary, protected_only: bool) -> Dictionary:
	var hero: Dictionary = board["hero"]
	if hero.is_empty() or not bool(heal.get("heal_target_is_hero", false)) or str(heal.get("healer_id", "")) != str(hero["id"]):
		return {}
	var cell := _hold_cell(loop, board, hero, [])
	var planned: Variant = _planned_cell(heal, str(hero["id"]))
	if planned is Vector2i and planned == cell:
		return {}
	return _heal_candidate(loop, board, protected_only, cell)


## Cure a poisoned player-side unit with a poison-curing item (ItemUseRules.first_status_slot,
## the rules' own cure scan — level 5's 解毒草): the healer moves next to the target (a self-cure
## to its least-threatened reachable cell) and uses it; others act greedily. The target's risk
## numbers drop its poison tick (_hero_numbers `cured_ids`); `heal_hp` carries the tick the
## cure prevents (one expected tick: the remaining poison turns are not shown to the player)
## so the scorer weighs it like a heal. {} when nobody is poisoned or no commandable unit still to act holds a cure.
static func _cure_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var plan := _cure_intent(loop, board)
	if plan.is_empty():
		return {}
	var hero: Dictionary = board["hero"]
	var target := Loop.unit(loop, str(plan["target_id"]))
	var hero_cell: Variant = null
	var hero_step := {}
	if not hero.is_empty() and str(plan["healer_id"]) == str(hero["id"]):
		hero_cell = plan["cell"]
	var damage := 0.0
	var kills := 0
	var actor_step := {"cell": plan["cell"]} if str(plan["healer_id"]) == str(board["actor_id"]) else {}
	var cells := {str(plan["healer_id"]): plan["cell"]}
	var kill_ids: Array = []
	for unit in board["commandables"]:
		if str(unit["id"]) == str(plan["healer_id"]):
			continue
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(hero.get("id", "")):
			hero_cell = step["cell"]
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	var numbers := _hero_numbers(loop, board, hero_cell, str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids, [str(plan["target_id"])])
	var out := _candidate("cure:%s" % str(plan["target_id"]), "cure", "%s uses a poison cure on %s (hp %d/%d); others act greedily." % [str(plan["healer_id"]), str(plan["target_id"]), int(target["hp"]), int(target["max_hp"])], damage, kills, numbers, cells, kill_ids)
	out["heal_hp"] = int(plan["prevented_hp"])
	out["heal_target_hp_ratio"] = snappedf(float(int(target["hp"]) - _poison_tick_hp(target, false)) / maxf(1.0, float(target["max_hp"])), 0.01)
	out["heal_target_is_hero"] = str(plan["target_id"]) == str(hero.get("id", ""))
	out["heal_target_protected"] = out["heal_target_is_hero"] or board["guarded"].has(str(plan["target_id"]))
	out["healer_id"] = str(plan["healer_id"])
	out["target_id"] = str(plan["target_id"])
	out["item_code"] = str(plan["item_code"])
	return out


## {healer_id, target_id, item_code, slot, cell, prevented_hp} for the poisoned player-side unit
## a commandable unit still to act (_pending_ids) can cure with an item: the hero or a guarded
## unit first, then the one a tick leaves lowest (HP ratio after one expected tick); ties go to
## a self-cure, then the earlier-listed healer. {} when none.
static func _cure_intent(loop: Dictionary, board: Dictionary) -> Dictionary:
	var best := {}
	var pending := _pending_ids(loop)
	var protected: Array = board["guarded"].duplicate()
	if not board["hero"].is_empty():
		protected.append(str(board["hero"]["id"]))
	for unit in board["commandables"]:
		if not unit.get("inventory") is Array or not pending.has(str(unit["id"])):
			continue
		var curing := ItemUse.first_status_slot(unit["inventory"], loop["consumables"], Status.POISON)
		if not bool(curing.get("ok", false)) or int(curing["index"]) < 0:
			continue
		var slot := int(curing["index"])
		var code := str(int(unit["inventory"][slot]))
		var definition: Dictionary = loop["consumables"][code]
		for target in loop["units"]:
			if not Loop.Presence.living(target) or str(target.get("battle_actor_role", "")) not in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]:
				continue
			if (int(target.get("status_flags", 0)) & Status.POISON) == 0:
				continue
			var effect := ItemUse.prepare(target, definition)
			if not bool(effect.get("ok", false)) or not bool(effect.get("cured_poison", false)):
				continue
			var cell: Variant = _adjacent_cell(loop, board, unit, target)
			if cell == null:
				continue
			var tick := _poison_tick_hp(target, false)
			var ratio := float(int(target["hp"]) - tick) / maxf(1.0, float(target["max_hp"]))
			var key := [0 if protected.has(str(target["id"])) else 1, ratio, 0 if str(unit["id"]) == str(target["id"]) else 1]
			if best.is_empty() or key < best["key"]:
				best = {"healer_id": str(unit["id"]), "target_id": str(target["id"]), "item_code": code, "slot": slot, "cell": cell, "prevented_hp": tick, "key": key}
	return best


## The hero moves to its reachable cell nearest (on foot) an escape cell (onto one when it
## can) and strikes from there only when the strike kills — a runner does not trade blows with
## its pursuers (level 53: 6 damage dealt, 10 taken on the counter); others act greedily. {}
## when the battle has no live escape objective or the hero is not commandable this round.
static func _escape_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var hero: Dictionary = board["hero"]
	var zone: Array = loop.get("escape_zone", [])
	if hero.is_empty() or str(loop.get("objective_phase", "")) != "escape" or zone.is_empty():
		return {}
	if not board["commandables"].any(func(unit): return str(unit["id"]) == str(hero["id"])):
		return {}
	var cell := _escape_cell(loop, board, hero)
	var strike := _escape_strike(loop, hero, cell)
	var damage := float(strike.get("expected_damage", 0.0))
	var kills := int(strike.get("kills", 0))
	var actor_step := {}
	var cells := {}
	var kill_ids: Array = []
	strike["cell"] = cell
	_record_step(cells, kill_ids, str(hero["id"]), strike)
	for unit in board["commandables"]:
		if str(unit["id"]) == str(hero["id"]):
			continue
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	var before := _escape_distance(loop, hero, hero["coord"])
	var after := _escape_distance(loop, hero, cell)
	var numbers := _hero_numbers(loop, board, cell, str(strike.get("foe_id", "")), int(strike.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids)
	# The runner's exposure is read with its body moved to the cell (see _pursuers_reaching).
	var pursuers := _pursuers_reaching(loop, board, hero, cell).filter(func(id): return not kill_ids.has(str(id)))
	var incoming := _expected_incoming(loop, hero, pursuers)
	var hp := maxf(1.0, float(hero.get("hp", 0)))
	numbers["hero_threat_after"] = pursuers.size()
	numbers["hero_expected_incoming_after"] = snappedf(incoming, 0.1)
	numbers["hero_risk"] = snappedf(minf(incoming / hp, 2.0), 0.01)
	numbers["hero_can_die"] = _worst_incoming(loop, hero, pursuers, true) >= int(hp)
	numbers["hero_expected_death"] = incoming >= hp
	var out := _candidate("escape", "escape", "The hero moves toward the escape zone (walking distance %d -> %d); others act greedily." % [before, after], damage, kills, numbers, cells, kill_ids)
	out["escape_distance_before"] = before
	out["escape_distance_after"] = after
	out["escape_reached"] = after == 0
	return out


## The hero's weapon strike from `cell` when it kills; {} otherwise (the runner keeps its HP).
static func _escape_strike(loop: Dictionary, hero: Dictionary, cell: Vector2i) -> Dictionary:
	var strike := _best_strike_from(loop, hero, cell)
	return strike if int(strike.get("kills", 0)) > 0 else {}


## Reachable cell nearest an escape cell on foot (ties: fewer foes that reach it once the
## runner has left its current cell, shorter path); the unit's own anchor must stand on the
## cell, as the loop's arrival check reads it.
static func _escape_cell(loop: Dictionary, board: Dictionary, unit: Dictionary) -> Vector2i:
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		var key := [_escape_distance(loop, unit, cell), _pursuers_reaching(loop, board, unit, cell).size(), _path_cost(loop, unit, cell)]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


## Foes whose move + weapon reach touches `unit` standing on `cell` with the unit moved there
## — the board's threat map is flooded around the unit's current body, which in a corridor
## blocks the pursuers' only path (level 53, (5,31): the guard two cells behind read as unable
## to reach the cell ahead, then walked through the vacated corridor and struck).
static func _pursuers_reaching(loop: Dictionary, board: Dictionary, unit: Dictionary, cell: Vector2i) -> Array:
	var moved: Dictionary = unit.duplicate()
	moved["coord"] = cell
	moved["grid_coord"] = cell
	var units: Array = []
	for other in loop.get("units", []):
		if not Loop.Presence.living(other):
			continue
		units.append(moved if str(other["id"]) == str(unit["id"]) else other)
	var body: Array = Loop.Footprint.cells(moved)
	var out: Array = []
	for foe in board["enemies"]:
		if bool(foe.get("no_attack", false)):
			continue
		var pattern := Loop.weapon_pattern(loop, foe)
		if not bool(pattern.get("ok", false)):
			continue
		var envelope: Dictionary = Loop.TacticalGridRules.movement_reachability_envelope(foe, units, Loop.TerrainEdits.tiles(loop), loop["map_size"])
		var origins: Array = envelope.get("reachable_coords", []).duplicate()
		origins.append(foe["coord"])
		var touched := false
		for origin in origins:
			for point in Loop.TacticalGridRules.attack_pattern_cells(origin, pattern["offsets"], loop["map_size"]):
				if body.has(point):
					touched = true
					break
			if touched:
				break
		if touched:
			out.append(str(foe["id"]))
	return out


## Walking distance from `cell` to the nearest escape cell for `unit` (movement cost of the
## rules' own flood over the bare terrain); ESCAPE_UNREACHABLE when no route exists.
static func _escape_distance(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> int:
	return int(_escape_field(loop, unit).get(cell, ESCAPE_UNREACHABLE))


## Walking distance fields memoized per scenario (terrain does not change during a battle):
## scenario + unit traversal kind + target cells -> {cell: cost}.
static var _walk_fields: Dictionary = {}


## Cost of every cell to the escape zone (_walk_field over loop escape_zone).
static func _escape_field(loop: Dictionary, unit: Dictionary) -> Dictionary:
	return _walk_field(loop, unit, loop.get("escape_zone", []))


## Cost of every cell to the nearest of `targets`: TacticalGridRules.movement_reachability_envelope
## flooded from each target with an unbounded budget over the terrain alone (no other units —
## foes move, walls do not), minimum over the targets. Climb costs are read in the flood's
## direction, so a slope costs a little differently than walked; the ordering along a route is
## what the planner reads.
static func _walk_field(loop: Dictionary, unit: Dictionary, targets: Array) -> Dictionary:
	var key := "%s|%s|%s|%s" % [str(loop.get("scenario_path", "")), str(loop.get("map_size", Vector2i.ZERO)), str(unit.get("traversal", {})), str(targets)]
	if _walk_fields.has(key):
		return _walk_fields[key]
	var field := {}
	for target in targets:
		var probe: Dictionary = unit.duplicate(true)
		probe["coord"] = target
		probe["grid_coord"] = target
		var envelope: Dictionary = Loop.TacticalGridRules.movement_reachability_envelope(probe, [probe], Loop.TerrainEdits.tiles(loop), loop["map_size"], ESCAPE_UNREACHABLE - 1)
		if not bool(envelope.get("ok", false)):
			continue
		field[target] = 0
		for routes in [envelope.get("reachable_by_coord", {}), envelope.get("transit_by_coord", {})]:
			for coord in routes:
				var cost := int(routes[coord]["cost"])
				if not field.has(coord) or cost < int(field[coord]):
					field[coord] = cost
	_walk_fields[key] = field
	return field


## Walking distance for `unit` standing on `cell` to objective target `target` (the field flooded
## from the target's cell, so the cells beside it cost one step); ESCAPE_UNREACHABLE when no route.
static func _march_distance(loop: Dictionary, unit: Dictionary, cell: Vector2i, target: Dictionary) -> int:
	return int(_walk_field(loop, unit, [target["coord"]]).get(cell, ESCAPE_UNREACHABLE))


## Foes at least one commandable unit can strike this round, weakest first (ties: nearest to the hero).
static func _focus_targets(loop: Dictionary, board: Dictionary) -> Array:
	var strikable: Array = []
	for foe in board["enemies"]:
		for unit in board["commandables"]:
			if not _strike_cells(loop, unit, foe).is_empty():
				strikable.append(foe)
				break
	var hero: Dictionary = board["hero"]
	strikable.sort_custom(func(a, b):
		if int(a["hp"]) != int(b["hp"]):
			return int(a["hp"]) < int(b["hp"])
		if not hero.is_empty():
			return Loop.Footprint.distance(hero, a) < Loop.Footprint.distance(hero, b)
		return str(a["id"]) < str(b["id"]))
	return strikable.slice(0, FOCUS_CANDIDATES)


## Every commandable unit that can strike `foe` does so from its least-threatened strike
## cell; the rest move toward `foe` (striking whatever they can from there).
static func _focus_candidate(loop: Dictionary, board: Dictionary, foe: Dictionary) -> Dictionary:
	var damage := 0.0
	var attackers := 0
	var hero_cell: Variant = null
	var hero_foe := ""
	var hero_kills := false
	var actor_step := {}
	var others := 0.0
	var other_kills := 0
	var cells := {}
	var kill_ids: Array = []
	for unit in board["commandables"]:
		var cell: Variant = _focus_cell(loop, board, unit, foe)
		if cell is Vector2i and _tactics and _march_lethal(loop, board, unit, cell, {"foe_id": str(foe["id"]), "kills": 0}):
			cell = null
		if cell is Vector2i:
			attackers += 1
			damage += _expected_strike(unit, foe)
			cells[str(unit["id"])] = cell
			if str(unit["id"]) == str(board["hero"].get("id", "")):
				hero_cell = cell
				hero_foe = str(foe["id"])
			if str(unit["id"]) == str(board["actor_id"]):
				actor_step = {"cell": cell, "foe_id": str(foe["id"]), "kills": 0}
		else:
			var step := _greedy_intent(loop, board, unit, true, foe)
			others += float(step["expected_damage"])
			other_kills += int(step["kills"])
			_record_step(cells, kill_ids, str(unit["id"]), step)
			if str(unit["id"]) == str(board["hero"].get("id", "")):
				hero_cell = step["cell"]
				hero_foe = str(step.get("foe_id", ""))
				hero_kills = int(step.get("kills", 0)) > 0
			if str(unit["id"]) == str(board["actor_id"]):
				actor_step = step
	var kills := (1 if damage >= float(foe["hp"]) else 0) + other_kills
	if damage >= float(foe["hp"]) and not kill_ids.has(str(foe["id"])):
		kill_ids.append(str(foe["id"]))
	if hero_foe == str(foe["id"]):
		hero_kills = damage >= float(foe["hp"])
	if str(actor_step.get("foe_id", "")) == str(foe["id"]):
		actor_step["kills"] = 1 if damage >= float(foe["hp"]) else 0
	var out := _candidate("focus:%s" % str(foe["id"]), "focus", "Every commandable unit that can strike %s (hp %d/%d) does; the rest move toward it." % [str(foe["id"]), int(foe["hp"]), int(foe["max_hp"])], damage + others, kills, _hero_numbers(loop, board, hero_cell, hero_foe, hero_kills, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	out["target_id"] = str(foe["id"])
	out["attackers"] = attackers
	out["can_kill"] = damage >= float(foe["hp"])
	return out


## Every commandable unit puts its hardest blow this round on objective target `foe`
## (_objective_step: its best forecast cast on it or its weapon, whichever expects more, with no
## exposure veto — the captain is the battle); a unit that cannot reach it closes in (a guarded
## unit only where it survives, _guarded_cell) — a unit that cannot reach it marches on it
## (_march_step). Offered whenever an objective target lives, reachable or not: the march across
## rounds is the plan (user, level 6 with the chapter hand-off party: "直接打队长就赢了"; 1 of 6
## seeds won while the plan waited for the captain to come within reach, R5-L3). Level 52 once
## lost 20 rounds to a march that walked 雷歐納德 alone into 皇帝's reach (2 HP left): the hero
## now marches only onto cells he survives (_march_lethal) and the commitment
## (_march_commitment) never takes a plan that expects a must-survive death. Level 6 (chapter
## hand-off, 3 of 3 seeds lost before the march): 雷歐納德, 琥 and 漢克斯 each struck 隊長 guard024_1
## (93 HP, the 打倒隊長 of the win panel) from a cell two soldiers reached, so focus set each
## strike aside and weeks of 023s came instead; the win status that ends the battle is armed
## only for five rounds.
static func _objective_candidate(loop: Dictionary, board: Dictionary, foe: Dictionary) -> Dictionary:
	var damage := 0.0
	var on_target := 0.0
	var attackers := 0
	var hero_cell: Variant = null
	var hero_foe := ""
	var actor_step := {}
	var cells := {}
	var kill_ids: Array = []
	var assignment := _strike_assignment(loop, board, foe)
	for unit in board["commandables"]:
		var step := _objective_step(loop, board, unit, foe, assignment)
		damage += float(step["expected_damage"])
		if str(step["foe_id"]) == str(foe["id"]):
			on_target += float(step["expected_damage"])
			attackers += 1
		cells[str(unit["id"])] = step["cell"]
		if str(unit["id"]) == str(board["hero"].get("id", "")):
			hero_cell = step["cell"]
			hero_foe = str(step["foe_id"])
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = {"cell": step["cell"], "foe_id": str(step["foe_id"]), "kills": 0}
	var kills := 1 if on_target >= float(foe["hp"]) else 0
	if kills > 0:
		kill_ids.append(str(foe["id"]))
		if str(actor_step.get("foe_id", "")) == str(foe["id"]):
			actor_step["kills"] = 1
	var out := _candidate("objective:%s" % str(foe["id"]), "objective", "Every commandable unit puts its hardest blow on the objective %s (hp %d/%d); the rest close in on it." % [str(foe["id"]), int(foe["hp"]), int(foe["max_hp"])], damage, kills, _hero_numbers(loop, board, hero_cell, hero_foe, kills > 0 and hero_foe == str(foe["id"]), actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	out["target_id"] = str(foe["id"])
	out["attackers"] = attackers
	out["assigned"] = assignment.size()
	out["objective"] = true
	out["can_kill"] = kills > 0
	return out


## `unit`'s blow on objective target `foe` this round: {cell, foe_id, expected_damage, cast} —
## its entry in `assignment` (_strike_assignment: the cell and weapon or cast the attack-cell
## assignment gave it), else the march toward `foe` (_march_step; foe_id "" unless the unit's
## weapon touches something there). A guarded unit keeps _guarded_cell's veto: it does not step
## where the threatening foes kill it.
static func _objective_step(loop: Dictionary, board: Dictionary, unit: Dictionary, foe: Dictionary, assignment: Dictionary) -> Dictionary:
	var id := str(unit["id"])
	if assignment.has(id):
		var option: Dictionary = assignment[id]
		return {"cell": option["cell"], "foe_id": str(foe["id"]), "expected_damage": float(option["damage"]), "cast": option["cast"]}
	var march := _march_step(loop, board, unit, foe)
	var cell := _guarded_cell(loop, board, unit, march["cell"])
	if cell != march["cell"]:
		var strike := _best_strike_from(loop, unit, cell)
		march = {"cell": cell, "foe_id": str(strike.get("foe_id", "")), "expected_damage": float(strike.get("expected_damage", 0.0))}
	return {"cell": march["cell"], "foe_id": str(march["foe_id"]), "expected_damage": float(march["expected_damage"]), "cast": {}}


## Attack-cell assignment: which commandable unit still to act this round (_pending_ids; every
## commandable unit without a queue) strikes `foe` from which cell, with its weapon or which
## cast — {unit id: {cell, damage, cast, threats, path}}. Every unit's options are its strike
## cells on `foe` (weapon, _strike_cells) and its forecast casts centred on it (_cast_intents),
## the best one per cell (ASSIGNMENT_OPTIONS of them, most damage on `foe` first); the search
## gives each unit at most one option and no two units the same cell, and keeps the assignment
## with the most damage on `foe` up to its HP, then the most damage, then the fewest threatening
## foes on the chosen cells, then the shortest paths. A guarded unit is offered only the cells
## _guarded_cell lets it stand on. Planned per unit, every unit took its own best cell: level 6
## (user kit memoir_05, round 2) had 雷歐納德, 琥 and 緹娜 all planned onto (25,6) and 琥's bow on
## the one open cell beside 隊長 that 漢克斯' dagger needed — two of four blows landed on him.
static func _strike_assignment(loop: Dictionary, board: Dictionary, foe: Dictionary) -> Dictionary:
	var pending := _pending_ids(loop)
	var rows: Array = []
	for unit in board["commandables"]:
		if not pending.is_empty() and not pending.has(str(unit["id"])):
			continue
		var options := _strike_options(loop, board, unit, foe)
		if not options.is_empty():
			rows.append({"id": str(unit["id"]), "options": options})
	var best := {"key": [], "picks": {}}
	_assign_search(rows, 0, {}, {}, float(foe["hp"]), best)
	return best["picks"]


## Options of one unit against `foe` for _strike_assignment: the best option per cell, at most
## ASSIGNMENT_OPTIONS, most damage on `foe` first (ties: fewer threats, shorter path).
static func _strike_options(loop: Dictionary, board: Dictionary, unit: Dictionary, foe: Dictionary) -> Array:
	var by_cell := {}
	var weapon := _expected_strike(unit, foe)
	for cell in _strike_cells(loop, unit, foe):
		by_cell[cell] = {"cell": cell, "damage": weapon, "value": weapon, "cast": {}, "threats": _threatening(loop, board, unit, cell).size(), "path": _path_cost(loop, unit, cell)}
	for row in _skill_options(loop, unit):
		for intent in _cast_intents(loop, board, unit, row["option"], row["descriptor"]):
			if str(intent["target_id"]) != str(foe["id"]):
				continue
			var on_target := float((intent.get("damage_by_target", {}) as Dictionary).get(str(foe["id"]), 0.0))
			if on_target <= 0.0:
				continue
			var value := on_target - _cost_penalty(str(intent["resource"]), int(intent["cost"]))
			var cell: Vector2i = intent["cell"]
			if not by_cell.has(cell) or value > float(by_cell[cell]["value"]):
				by_cell[cell] = {"cell": cell, "damage": on_target, "value": value, "cast": intent, "threats": int(intent["threats"]), "path": int(intent["path_cost"])}
	var out: Array = []
	for cell in by_cell:
		if _guarded_cell(loop, board, unit, cell) == cell:
			out.append(by_cell[cell])
	out.sort_custom(func(a, b):
		if float(a["value"]) != float(b["value"]):
			return float(a["value"]) > float(b["value"])
		if int(a["threats"]) != int(b["threats"]):
			return int(a["threats"]) < int(b["threats"])
		return int(a["path"]) < int(b["path"]))
	return out.slice(0, ASSIGNMENT_OPTIONS)


## Depth-first search of _strike_assignment: row `index` takes one of its options on a free cell
## or none; `best` holds the best {key, picks} seen.
static func _assign_search(rows: Array, index: int, used: Dictionary, picks: Dictionary, hp: float, best: Dictionary) -> void:
	if index == rows.size():
		var damage := 0.0
		var threats := 0
		var path := 0
		for id in picks:
			damage += float(picks[id]["value"])
			threats += int(picks[id]["threats"])
			path += int(picks[id]["path"])
		var key := [-minf(damage, hp), -damage, threats, path]
		if best["key"].is_empty() or key < best["key"]:
			best["key"] = key
			best["picks"] = picks.duplicate()
		return
	var row: Dictionary = rows[index]
	for option in row["options"]:
		if used.has(option["cell"]):
			continue
		used[option["cell"]] = true
		picks[row["id"]] = option
		_assign_search(rows, index + 1, used, picks, hp, best)
		picks.erase(row["id"])
		used.erase(option["cell"])
	_assign_search(rows, index + 1, used, picks, hp, best)


## The march on objective target `foe` for a unit that cannot strike it this round: the reachable
## cell with the least walking distance to it (_march_distance: around walls, not Manhattan;
## ties: fewer threatening foes, then staying put), or a cell at most MARCH_SLACK steps farther
## from which it strikes a foe on the way (the weakest, _best_strike_from) — fighting through
## the guards instead of stepping back out of their reach. No reach-rule hold: the march is
## priced by the candidate's exposure numbers and the valuation. The hero and guarded units
## march only onto cells where the foes that reach them cannot kill them (worst case with a
## critical, _worst_incoming) while such a cell exists (level 6, chapter hand-off, seed 6:
## 雷歐納德 at 30/39 walked up to the captain's guards and fell to 7 + 7 + 29 before anyone
## struck 隊長). {cell, foe_id, expected_damage}.
static func _march_step(loop: Dictionary, board: Dictionary, unit: Dictionary, foe: Dictionary) -> Dictionary:
	var careful: bool = str(unit["id"]) == str(board["hero"].get("id", "")) or board["guarded"].has(str(unit["id"]))
	var best := {}
	var best_key: Array = []
	var rows: Array = []
	for cell in _reachable(loop, unit):
		var strike := _best_strike_from(loop, unit, cell)
		var row := {"cell": cell, "distance": _march_distance(loop, unit, cell, foe), "threats": _threatening(loop, board, unit, cell).size(), "strike": strike, "lethal": 1 if careful and _march_lethal(loop, board, unit, cell, strike) else 0}
		rows.append(row)
		var key := [row["lethal"], row["distance"], row["threats"], 0 if cell == unit["coord"] else 1]
		if best_key.is_empty() or key < best_key:
			best = row
			best_key = key
	var pick: Dictionary = best
	if (best["strike"] as Dictionary).is_empty():
		var pick_key: Array = []
		for row in rows:
			if (row["strike"] as Dictionary).is_empty() or int(row["distance"]) > int(best["distance"]) + MARCH_SLACK or int(row["lethal"]) > int(best["lethal"]):
				continue
			var key := [int(row["strike"]["hp"]), row["distance"], row["threats"]]
			if pick_key.is_empty() or key < pick_key:
				pick = row
				pick_key = key
	var strike: Dictionary = pick["strike"]
	return {"cell": pick["cell"], "foe_id": str(strike.get("foe_id", "")), "expected_damage": float(strike.get("expected_damage", 0.0))}


## True when `unit` standing on `cell` and making `strike` (_best_strike_from there, {} for
## none) could die this round: every foe reaching the cell but the one the strike kills landing
## its preview damage with one critical, plus the struck foe's counter (_counter_numbers worst).
static func _march_lethal(loop: Dictionary, board: Dictionary, unit: Dictionary, cell: Vector2i, strike: Dictionary) -> bool:
	var killed := str(strike.get("foe_id", "")) if int(strike.get("kills", 0)) > 0 else ""
	var threats := _threatening(loop, board, unit, cell).filter(func(id): return str(id) != killed)
	var counter := _counter_numbers(loop, unit, cell, str(strike.get("foe_id", "")), killed != "")
	return _worst_incoming(loop, unit, threats, true) + int(counter["worst"]) >= int(unit.get("hp", 0))


## One caster casts `intent` (skill at its forecast cast); every other commandable unit acts greedily.
static func _skill_candidate(loop: Dictionary, board: Dictionary, intent: Dictionary) -> Dictionary:
	var hero: Dictionary = board["hero"]
	var caster_id := str(intent["caster_id"])
	var damage := float(intent["expected_damage"])
	var kills := int(intent["kills"])
	var hero_cell: Variant = null
	var hero_step := {}
	var actor_step := {"cell": intent["cell"]} if caster_id == str(board["actor_id"]) else {}
	var cells := {caster_id: intent["cell"]}
	var kill_ids: Array = []
	if int(intent["kills"]) > 0:
		kill_ids.append(str(intent["target_id"]))
	for unit in board["commandables"]:
		if str(unit["id"]) == caster_id:
			if caster_id == str(hero.get("id", "")):
				hero_cell = intent["cell"]
			continue
		var step := _greedy_intent(loop, board, unit, false)
		damage += float(step["expected_damage"])
		kills += int(step["kills"])
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(hero.get("id", "")):
			hero_cell = step["cell"]
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	var target := Loop.unit(loop, str(intent["target_id"]))
	var summary := "%s casts %s (%s %d) at %s (hp %d/%d) from (%d,%d): %d target(s), forecast damage %.1f, healing %d; others act greedily." % [caster_id, str(intent["skill_name"]), str(intent["resource"]), int(intent["cost"]), str(intent["target_id"]), int(target.get("hp", 0)), int(target.get("max_hp", 0)), intent["cell"].x, intent["cell"].y, int(intent["targets_hit"]), float(intent["expected_damage"]), int(intent["heal_hp"])]
	var out := _candidate("%s:%s@%s" % [str(intent["channel"]), str(intent["skill_id"]), str(intent["target_id"])], str(intent["channel"]), summary, damage, kills, _hero_numbers(loop, board, hero_cell, str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	for key in ["caster_id", "skill_id", "target_id", "targets_hit", "heal_hp", "resource", "cost", "resource_after"]:
		out[key] = intent[key]
	out["cast_center"] = [intent["cast_center"].x, intent["cast_center"].y]
	out["cast_damage"] = snappedf(float(intent["expected_damage"]), 0.1)
	out["objective"] = float(intent["expected_damage"]) > 0.0 and board["objectives"].has(str(intent["target_id"]))
	if int(intent["heal_hp"]) > 0:
		out["heal_target_hp_ratio"] = snappedf(float(target["hp"]) / maxf(1.0, float(target["max_hp"])), 0.01)
		out["heal_target_is_hero"] = str(intent["target_id"]) == str(hero.get("id", ""))
	return out


# ----------------------------------------------------------------------------- lookahead candidates

## Every commandable unit moves to a reachable cell no foe can strike this round (hero placed
## first, then the others nearest the hero), keeping within COHESION_DISTANCE of a unit already
## placed and as close to the foes as safety allows (one cell outside their reach), striking
## whatever its weapon touches from there. Without a safe cell a unit takes its safest one.
static func _hold_line_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var damage := 0.0
	var kills := 0
	var cells := {}
	var kill_ids: Array = []
	var anchors: Array = []
	var actor_step := {}
	var hero_step := {}
	var pending := _pending_ids(loop)
	for unit in _hero_first(board):
		var cell: Vector2i = unit["coord"] if not pending.is_empty() and not pending.has(str(unit["id"])) else _hold_cell(loop, board, unit, anchors)
		anchors.append(cell)
		var step := _best_strike_from(loop, unit, cell)
		step["cell"] = cell
		damage += float(step.get("expected_damage", 0.0))
		kills += int(step.get("kills", 0))
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["hero"].get("id", "")):
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	return _candidate("hold_line", "hold_line", "Every commandable unit holds a cell outside every foe's reach, grouped, as near the foes as that allows.", damage, kills, _hero_numbers(loop, board, hero_step.get("cell"), str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)


## Commandable units, the hero first, then by distance to the hero (ties: id).
static func _hero_first(board: Dictionary) -> Array:
	var hero: Dictionary = board["hero"]
	var units: Array = board["commandables"].duplicate()
	units.sort_custom(func(a, b):
		var a_hero := str(a["id"]) == str(hero.get("id", ""))
		var b_hero := str(b["id"]) == str(hero.get("id", ""))
		if a_hero != b_hero:
			return a_hero
		if not hero.is_empty():
			var da := Loop.Footprint.distance(hero, a)
			var db := Loop.Footprint.distance(hero, b)
			if da != db:
				return da < db
		return str(a["id"]) < str(b["id"]))
	return units


## hold_line's cell for `unit`: fewest threatening foes (0 when any), then the smallest
## cohesion breach (cells beyond COHESION_DISTANCE from the nearest anchor), then nearest to a
## foe, then the shortest path. An anchor cell (a cell already given to another unit) is never
## given again: planned alone, every unit of memoir_05's round 1 (level 6) took the same least-
## threatened cell (22,8), the plan's numbers read four bodies on one cell and the grounding sent
## all but the first to their own safest cells, away from the line.
static func _hold_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, anchors: Array) -> Vector2i:
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		if anchors.has(cell):
			continue
		var cohesion := 0
		if not anchors.is_empty():
			var nearest := -1
			for anchor in anchors:
				var distance := absi(cell.x - anchor.x) + absi(cell.y - anchor.y)
				if nearest < 0 or distance < nearest:
					nearest = distance
			cohesion = maxi(0, nearest - COHESION_DISTANCE)
		var key := [_threatening(loop, board, unit, cell).size(), cohesion, _nearest_foe_distance(unit, cell, board["enemies"]), _path_cost(loop, unit, cell)]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


## Commandable units by HP + defense, toughest first: bait candidates are tried in this order.
static func _bait_units(board: Dictionary) -> Array:
	var units: Array = board["commandables"].duplicate()
	units.sort_custom(func(a, b):
		var ta := int(a.get("hp", 0)) + int(Combat.combat_profile_from_unit(a).get("live_defense", 0))
		var tb := int(b.get("hp", 0)) + int(Combat.combat_profile_from_unit(b).get("live_defense", 0))
		if ta != tb:
			return ta > tb
		return str(a["id"]) < str(b["id"]))
	return units


## `bait` stands on a reachable cell exactly one foe can strike this round (preferring a cell
## it survives that foe's worst strike on, then the weakest such foe, then the shortest path);
## every other commandable unit takes a cell no foe can strike, as near as possible to the
## cells that foe would strike the bait from, so that it can be struck next round. {} when no
## cell exactly one foe reaches exists.
static func _bait_candidate(loop: Dictionary, board: Dictionary, bait: Dictionary) -> Dictionary:
	var bait_cell: Variant = null
	var best_key: Array = []
	var foe_id := ""
	for cell in _reachable(loop, bait):
		var ids := _threatening(loop, board, bait, cell)
		if ids.size() != 1:
			continue
		var foe := Loop.unit(loop, str(ids[0]))
		var key := [0 if _worst_incoming(loop, bait, ids) < int(bait.get("hp", 0)) else 1, int(foe.get("hp", 0)), _path_cost(loop, bait, cell)]
		if bait_cell == null or key < best_key:
			bait_cell = cell
			best_key = key
			foe_id = str(ids[0])
	if bait_cell == null:
		return {}
	var foe := Loop.unit(loop, foe_id)
	var strike_from: Array = []
	var pattern := Loop.weapon_pattern(loop, foe)
	if bool(pattern.get("ok", false)):
		var origins: Array = _movement_cells(loop, foe_id).duplicate()
		origins.append(foe["coord"])
		for origin in origins:
			if Loop.Footprint.overlaps(bait, Loop.TacticalGridRules.attack_pattern_cells(origin, pattern["offsets"], loop["map_size"]), bait_cell):
				strike_from.append(origin)
	var damage := 0.0
	var kills := 0
	var cells := {}
	var kill_ids: Array = []
	var actor_step := {}
	var hero_step := {}
	var taken: Array = [bait_cell]
	for unit in board["commandables"]:
		var cell: Vector2i = bait_cell if str(unit["id"]) == str(bait["id"]) else _support_cell(loop, board, unit, strike_from, taken)
		taken.append(cell)
		var step := _best_strike_from(loop, unit, cell)
		step["cell"] = cell
		damage += float(step.get("expected_damage", 0.0))
		kills += int(step.get("kills", 0))
		_record_step(cells, kill_ids, str(unit["id"]), step)
		if str(unit["id"]) == str(board["hero"].get("id", "")):
			hero_step = step
		if str(unit["id"]) == str(board["actor_id"]):
			actor_step = step
	var out := _candidate("bait:%s" % str(bait["id"]), "bait", "%s stands where only %s can strike it (%d,%d); the others hold outside every foe's reach near the cells %s would strike from." % [str(bait["id"]), foe_id, bait_cell.x, bait_cell.y, foe_id], damage, kills, _hero_numbers(loop, board, hero_step.get("cell"), str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)
	out["bait_id"] = str(bait["id"])
	out["bait_foe_id"] = foe_id
	return out


## Reachable cell outside `taken` (cells already given to other units) with the fewest threatening
## foes, then nearest to any of `goals`, then the shortest path.
static func _support_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, goals: Array, taken: Array = []) -> Vector2i:
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		if taken.has(cell):
			continue
		var nearest := 0
		if not goals.is_empty():
			nearest = -1
			for goal in goals:
				var distance := absi(cell.x - goal.x) + absi(cell.y - goal.y)
				if nearest < 0 or distance < nearest:
					nearest = distance
		var key := [_threatening(loop, board, unit, cell).size(), nearest, _path_cost(loop, unit, cell)]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


## Every commandable unit still to act takes a distinct cell of one block around the hero's cell
## (the hero within FORMATION_RADIUS of where it stands, every other unit within COHESION_DISTANCE
## of a unit already placed, hero first) and strikes the weakest foe its weapon touches from there:
## the party fights together where it stands and lets the foes come (_formation_cell). A unit that
## has acted keeps its cell. Without a commandable hero the first unit in roster order anchors.
static func _formation_candidate(loop: Dictionary, board: Dictionary) -> Dictionary:
	var pending := _pending_ids(loop)
	var damage := 0.0
	var kills := 0
	var cells := {}
	var kill_ids: Array = []
	var placed: Array = []
	var actor_step := {}
	var hero_step := {}
	var units := _hero_first(board)
	var anchor: Vector2i = (board["hero"] if board["commandables"].has(board["hero"]) else units[0])["coord"]
	for unit in units:
		var id := str(unit["id"])
		var step := {}
		if not pending.is_empty() and not pending.has(id):
			step = {"cell": unit["coord"]}
		else:
			var cell := _formation_cell(loop, board, unit, anchor, placed)
			step = _best_strike_from(loop, unit, cell)
			step["cell"] = cell
		placed.append(step["cell"])
		damage += float(step.get("expected_damage", 0.0))
		kills += int(step.get("kills", 0))
		_record_step(cells, kill_ids, id, step)
		if id == str(board["hero"].get("id", "")):
			hero_step = step
		if id == str(board["actor_id"]):
			actor_step = step
	return _candidate("formation", "formation", "Every commandable unit takes a cell of one block around the hero and strikes the weakest foe in reach from there.", damage, kills, _hero_numbers(loop, board, hero_step.get("cell"), str(hero_step.get("foe_id", "")), int(hero_step.get("kills", 0)) > 0, actor_step.get("cell"), actor_step, cells, kill_ids), cells, kill_ids)


## formation's cell for `unit`: a reachable cell not in `placed`, within FORMATION_RADIUS of
## `anchor` for the first unit and within COHESION_DISTANCE of a placed cell for the others (any
## reachable cell when none qualifies); the hero and guarded units never onto a cell where the
## foes reaching it would kill them while another exists (_march_lethal); then not exposed
## (REACH_LIMIT foes, the reach rule), then the most expected weapon damage (a kill counts
## WEIGHT_KILL more), then fewer threatening foes, then nearer the anchor.
static func _formation_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, anchor: Vector2i, placed: Array) -> Vector2i:
	var careful: bool = str(unit["id"]) == str(board["hero"].get("id", "")) or board["guarded"].has(str(unit["id"]))
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		if placed.has(cell):
			continue
		var near := 0
		if placed.is_empty():
			near = maxi(0, absi(cell.x - anchor.x) + absi(cell.y - anchor.y) - FORMATION_RADIUS)
		else:
			var nearest := -1
			for other in placed:
				var distance := absi(cell.x - other.x) + absi(cell.y - other.y)
				if nearest < 0 or distance < nearest:
					nearest = distance
			near = maxi(0, nearest - COHESION_DISTANCE)
		var strike := _best_strike_from(loop, unit, cell)
		var threats := _threatening(loop, board, unit, cell).filter(func(id): return int(strike.get("kills", 0)) == 0 or str(id) != str(strike.get("foe_id", "")))
		var value := float(strike.get("expected_damage", 0.0)) + WEIGHT_KILL * float(strike.get("kills", 0))
		var key := [near, 1 if careful and _march_lethal(loop, board, unit, cell, strike) else 0, 1 if threats.size() >= REACH_LIMIT else 0, -value, threats.size(), absi(cell.x - anchor.x) + absi(cell.y - anchor.y)]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


## Commandable must-survive units other than the hero (board.guarded, _escorted) standing farther
## than ISOLATION_DISTANCE from every other living party-side unit: the escort candidates' guards.
static func _apart_guards(loop: Dictionary, board: Dictionary) -> Array:
	var out: Array = []
	for id in board["guarded"]:
		var unit := Loop.unit(loop, str(id))
		if _escorted(unit) and _party_gap(loop, unit, unit["coord"]) > ISOLATION_DISTANCE:
			out.append(str(id))
	return out


## True for a living commandable player unit (a friendly AI escort does not move on the plan's word).
static func _escorted(unit: Dictionary) -> bool:
	return Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) == Loop.ROLE_PLAYER and bool(unit.get("player_commandable", false))


## The nearest other living party-side unit (player or friendly AI) to `unit` standing on `cell`
## (footprint-aware Manhattan; ties: roster order); {} when none.
static func _nearest_partner(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> Dictionary:
	var best := {}
	var best_distance := -1
	for other in loop.get("units", []):
		if str(other.get("id", "")) == str(unit.get("id", "")) or not Loop.Presence.living(other):
			continue
		if str(other.get("battle_actor_role", "")) not in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]:
			continue
		var distance := Loop.Footprint.distance(unit, other, cell)
		if best_distance < 0 or distance < best_distance:
			best = other
			best_distance = distance
	return best


## Distance from `unit` standing on `cell` to the nearest other living party-side unit; 0 when none.
static func _party_gap(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> int:
	var partner := _nearest_partner(loop, unit, cell)
	return 0 if partner.is_empty() else Loop.Footprint.distance(unit, partner, cell)


## escort:<guard>: the must-survive unit `guard`, apart from the party (_apart_guards), walks
## toward its nearest partner and every other commandable unit walks toward the guard's cell for
## the round (_escort_step: the march of _march_step over walking distance, striking on the way,
## the hero and guarded units only onto cells they survive). Valued like every plan; the evaluate
## `apart` term prices the gap the round leaves. {} when `guard` is not apart.
static func _escort_candidate(loop: Dictionary, board: Dictionary, guard: Dictionary) -> Dictionary:
	var guard_id := str(guard["id"])
	var pending := _pending_ids(loop)
	var guard_step := {}
	var guard_cell: Vector2i = guard["coord"]
	if pending.is_empty() or pending.has(guard_id):
		guard_step = _escort_step(loop, board, guard, guard)
		guard_cell = guard_step["cell"]
	var damage := 0.0
	var cells := {}
	var kill_ids: Array = []
	var actor_step := {}
	var hero_step := {}
	for unit in board["commandables"]:
		var id := str(unit["id"])
		var step: Dictionary = guard_step if id == guard_id else _escort_step(loop, board, unit, guard, guard_cell)
		if step.is_empty():
			continue
		damage += float(step["expected_damage"])
		_record_step(cells, kill_ids, id, step)
		if id == str(board["hero"].get("id", "")):
			hero_step = step
		if id == str(board["actor_id"]):
			actor_step = step
	var numbers := _hero_numbers(loop, board, hero_step.get("cell"), str(hero_step.get("foe_id", "")), false, actor_step.get("cell"), actor_step, cells, kill_ids)
	var out := _candidate("escort:%s" % guard_id, "escort", "%s (hp %d/%d), %d cells from the party, walks back toward it; the others walk toward (%d,%d)." % [guard_id, int(guard["hp"]), int(guard["max_hp"]), _party_gap(loop, guard, guard["coord"]), guard_cell.x, guard_cell.y], damage, 0, numbers, cells, kill_ids)
	out["target_id"] = guard_id
	return out


## One unit's move under escort:<guard>: the guard marches (_march_step) on its nearest partner,
## every other unit on `goal` (the guard's cell for the round; its current cell when null).
## {cell, foe_id, expected_damage}.
static func _escort_step(loop: Dictionary, board: Dictionary, unit: Dictionary, guard: Dictionary, goal: Variant = null) -> Dictionary:
	if str(unit["id"]) == str(guard["id"]):
		var partner := _nearest_partner(loop, unit, unit["coord"])
		if partner.is_empty():
			return {"cell": unit["coord"], "foe_id": "", "expected_damage": 0.0}
		return _march_step(loop, board, unit, {"coord": partner["coord"]})
	return _march_step(loop, board, unit, {"coord": goal if goal is Vector2i else guard["coord"]})


# ----------------------------------------------------------------------------- lookahead selection

## Party units the plan leaves on a cell REACH_LIMIT or more foes it does not kill can strike
## and together kill (_worst_incoming at or above its HP): [{unit, cell, foes}] (the hard reach
## rule's breaches).
static func reach_breaches(loop: Dictionary, board: Dictionary, candidate: Dictionary) -> Array:
	var out: Array = []
	var killed: Array = candidate.get("kill_ids", [])
	for unit in board["commandables"]:
		var cell: Variant = _planned_cell(candidate, str(unit["id"]))
		if not cell is Vector2i:
			cell = unit["coord"]
		var foes: Array = _threatening(loop, board, unit, cell).filter(func(id): return not killed.has(str(id)))
		if foes.size() >= REACH_LIMIT and _worst_incoming(loop, unit, foes) >= int(unit.get("hp", 0)):
			out.append({"unit": str(unit["id"]), "cell": [cell.x, cell.y], "foes": foes.size()})
	return out


## The lookahead pick: candidates that break the reach rule are set aside — except the escape
## plan and any plan that kills a foe, which are always simulated (a runner is within its
## pursuers' reach by definition, and a kill removes one of the foes the reach count fears;
## level 53 round 12: the 月花圓舞 cast that kills the gate guard blocking a one-cell corridor
## was set aside behind a -415 escape that never reached RELAX_BELOW_VALUE); the admitted ones
## (hold_line and bait first, then the scored order) are simulated (simulate_round) and valued
## (evaluate) within LOOKAHEAD_STEP_BUDGET simulated steps; when none was admitted, or the best
## still ends at RELAX_BELOW_VALUE or worse, or its own numbers say a must-survive unit can die
## where it leaves it (hero_can_die: level 53 round 12, a cornered runner whose only admitted
## plan was the escape into three pursuers while the holds beside it were never simulated),
## the set-aside ones get their own budget too (`relaxed`). Highest value wins (ties: scored score, then order); the brain's deadline
## stops every simulation and, with nothing simulated, the scored pick stands (`fallbacks`).
static func select_lookahead(brain: Dictionary, loop: Dictionary, board: Dictionary, options: Array) -> Dictionary:
	var admitted: Array = []
	var rejected: Array = []
	for candidate in options:
		var breaches := reach_breaches(loop, board, candidate)
		candidate["breaches"] = breaches.size()
		if breaches.is_empty() or _reach_exempt(candidate):
			admitted.append(candidate)
		else:
			rejected.append(candidate)
	brain["rejected"] += rejected.size()
	for index in range(options.size()):
		options[index]["order"] = index
	var weights := role_weights(loop, board)
	var budget := {"steps": 0, "simulated": 0}
	_ai_step_memo.clear()
	_ai_step_memo_open = true
	var best := _simulate_ranked(brain, loop, board, admitted, weights, budget)
	var challengers := _strike_challengers(rejected)
	if not challengers.is_empty() and not best.is_empty() and float(best["value"]) > RELAX_BELOW_VALUE and not bool(best.get("hero_can_die", false)):
		var challenger := _simulate_ranked(brain, loop, board, challengers, weights, {"steps": 0, "simulated": 0})
		if not challenger.is_empty() and float(challenger["value"]) > float(best["value"]):
			best = challenger
		rejected = rejected.filter(func(candidate): return not challengers.has(candidate))
	if not rejected.is_empty() and (best.is_empty() or float(best["value"]) <= RELAX_BELOW_VALUE or bool(best.get("hero_can_die", false))):
		brain["relaxed"] += 1
		budget = {"steps": 0, "simulated": 0}
		var relaxed := _simulate_ranked(brain, loop, board, rejected, weights, budget)
		if best.is_empty() or (not relaxed.is_empty() and float(relaxed["value"]) > float(best["value"])):
			best = relaxed
	_ai_step_memo_open = false
	_ai_step_memo.clear()
	if best.is_empty():
		brain["fallbacks"] += 1
		return select(options)
	var committed := _march_commitment(options, best)
	if not committed.is_empty():
		brain["committed"] += 1
		return committed
	return best


## The objective plan the commander stays committed to across rounds: a simulated objective:<foe>
## plan whose value is within MARCH_COMMITMENT of the best, whose own numbers leave no
## must-survive unit where the foes could kill it (hero_can_die, worst case; level 6 seed 12:
## a march kept with 雷歐納德 at 17/40 beside the captain, the 023 that reached him struck 20) and whose simulated round lost no
## must-survive unit (evaluate `deaths` above -VALUE_GUARDED_DEATH); {} otherwise or when the
## best already is one. A one-round valuation reads a march into the captain's guards as worse
## than holding every round, so without a commitment the march is never begun (level 6).
static func _march_commitment(options: Array, best: Dictionary) -> Dictionary:
	if bool(best.get("objective", false)):
		return {}
	var pick := {}
	for candidate in options:
		if not bool(candidate.get("objective", false)) or not candidate.has("value") or bool(candidate.get("hero_expected_death", false)) or bool(candidate.get("hero_can_die", false)):
			continue
		if float((candidate.get("valued", {}) as Dictionary).get("deaths", 0.0)) <= -VALUE_GUARDED_DEATH:
			continue
		if float(candidate["value"]) < float(best["value"]) - MARCH_COMMITMENT:
			continue
		if pick.is_empty() or float(candidate["value"]) > float(pick["value"]):
			pick = candidate
	return pick


## The set-aside plan that strikes hardest (highest scored damage among the focus / advance /
## rescue / cast plans the reach rule set aside), simulated beside the admitted ones whatever
## their values: [] or [that plan]. The reach rule reads "two foes reach this cell" as unsafe
## whatever the HP on both sides; a player with a full-HP party and three foes left attacks
## (level 5, chapter hand-off, seed 4: round 8, 3 foes left and 雷歐納德 35/39, 琥 42/42,
## 漢克斯 50/50 — every focus plan was set aside, the admitted holds walked 琥 and 漢克斯 away,
## and the round-9 wave found 雷歐納德 alone).
static func _strike_challengers(rejected: Array) -> Array:
	var best := {}
	for candidate in rejected:
		if str(candidate["kind"]) not in ["focus", "advance", "rescue", "magic", "special"] or float(candidate["expected_damage"]) <= 0.0:
			continue
		if best.is_empty() or float(candidate["score"]) > float(best["score"]):
			best = candidate
	return [] if best.is_empty() else [best]


## True when the loop's live objective is escape with an escape zone and the scenario offers
## no clear-the-field victory beside it (VALUE_ESCAPE_STEP).
static func _escape_is_sole_victory(loop: Dictionary) -> bool:
	return str(loop.get("objective_phase", "")) == "escape" and not loop.get("escape_zone", []).is_empty() and not bool(loop.get("allow_optional_clear_after_switch", false))


## Plans the reach rule never sets aside: the escape plan, any plan that kills a foe, and a heal
## or cure on the hero or a guarded unit (level 6, chapter hand-off: 雷歐納德 at 12/41 after a
## 023 and a guard struck him before his first turn; heal:leonard was set aside because 緹娜 stood
## where two foes reach, hold_line at -231 never fell to RELAX_BELOW_VALUE, and the same two
## struck him dead the next round for 9 + 19).
static func _reach_exempt(candidate: Dictionary) -> bool:
	return str(candidate["kind"]) in ["escape", "escort"] or int(candidate.get("kills", 0)) > 0 or bool(candidate.get("objective", false)) or (str(candidate["kind"]) in ["heal", "cure"] and bool(candidate.get("heal_target_protected", false)))


## Simulates `candidates` in priority order (fewest breaches — a reach-exempt plan counts as
## none —, hold_line / bait / escape, scored score, listing order) within the step budget; the
## best-valued one, {} when none was simulated.
static func _simulate_ranked(brain: Dictionary, loop: Dictionary, board: Dictionary, candidates: Array, weights: Dictionary, budget: Dictionary) -> Dictionary:
	var order := candidates.duplicate()
	order.sort_custom(func(a, b):
		var ka := [0 if _reach_exempt(a) else int(a["breaches"]), 0 if str(a["kind"]) in ["hold_line", "bait", "escape", "escort", "formation"] or bool(a.get("objective", false)) else 1, -float(a["score"]), int(a["order"])]
		var kb := [0 if _reach_exempt(b) else int(b["breaches"]), 0 if str(b["kind"]) in ["hold_line", "bait", "escape", "escort", "formation"] or bool(b.get("objective", false)) else 1, -float(b["score"]), int(b["order"])]
		return ka < kb)
	var best: Dictionary = {}
	for candidate in order:
		var deadline_passed: bool = int(brain.get("deadline_msec", 0)) > 0 and Time.get_ticks_msec() >= int(brain["deadline_msec"])
		if deadline_passed or (int(budget["steps"]) >= LOOKAHEAD_STEP_BUDGET and int(budget["simulated"]) >= LOOKAHEAD_MIN_SIMULATIONS):
			candidate["lookahead"] = "skipped"
			brain["skipped"] += 1
			continue
		var sim := simulate_round(loop, candidate)
		budget["simulated"] += 1
		budget["steps"] += int(sim["steps"])
		brain["simulations"] += 1
		brain["sim_msec"] = float(brain["sim_msec"]) + float(sim["msec"])
		if bool(sim["mutated"]):
			brain["mutations"] += 1
		var valued := evaluate(loop, sim["loop"], board, candidate, weights)
		candidate["value"] = valued["value"]
		candidate["valued"] = valued
		candidate["lookahead"] = "simulated" if bool(sim["complete"]) else "partial"
		candidate["sim_steps"] = int(sim["steps"])
		candidate["sim_msec"] = snappedf(float(sim["msec"]), 0.1)
		if best.is_empty() or float(candidate["value"]) > float(best["value"]) or (float(candidate["value"]) == float(best["value"]) and float(candidate["score"]) > float(best["score"])):
			best = candidate
	return best


## True when no other living party-side unit (player or friendly AI) stands within
## ISOLATION_DISTANCE cells (Manhattan, footprint-aware) of `unit` in `loop`.
static func _isolated(loop: Dictionary, unit: Dictionary) -> bool:
	return _isolated_at(loop, unit, unit["coord"])


## _isolated with `unit` standing on `cell` (the others where they stand).
static func _isolated_at(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> bool:
	for other in loop.get("units", []):
		if str(other.get("id", "")) == str(unit.get("id", "")) or not Loop.Presence.living(other):
			continue
		if str(other.get("battle_actor_role", "")) not in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]:
			continue
		if Loop.Footprint.distance(unit, other, cell) <= ISOLATION_DISTANCE:
			return false
	return true


## Role weight of every living party-side unit (id -> weight): hero and guarded (must-survive) units 1.0,
## the top weapon damage dealer (largest preview damage on the weakest living foe) and every
## healer (a support skill or a healing item) ROLE_KEY, every other unit with a forecastable
## damage skill ROLE_CASTER, other commandable units ROLE_OTHER, friendly AI units ROLE_FRIENDLY.
static func role_weights(loop: Dictionary, board: Dictionary) -> Dictionary:
	var weights := {}
	var hero_id := str(board["hero"].get("id", ""))
	var weakest := {}
	for foe in board["enemies"]:
		if weakest.is_empty() or int(foe["hp"]) < int(weakest["hp"]):
			weakest = foe
	var top_id := ""
	var top_damage := -1
	for unit in board["commandables"]:
		var id := str(unit["id"])
		var weight := ROLE_OTHER
		if id == hero_id or board["guarded"].has(id):
			weight = 1.0
		var healer := false
		if unit.get("inventory") is Array:
			var healing := ItemUse.first_healing_slot(unit["inventory"], loop["consumables"])
			healer = bool(healing.get("ok", false)) and int(healing.get("index", -1)) >= 0
		var caster := false
		for row in _skill_options(loop, unit):
			if str(row["descriptor"].get("damage_policy", "")) in SUPPORT_POLICIES:
				healer = true
			else:
				caster = true
		if healer:
			weight = maxf(weight, ROLE_KEY)
		elif caster:
			weight = maxf(weight, ROLE_CASTER)
		weights[id] = weight
		if not weakest.is_empty() and not bool(unit.get("no_attack", false)):
			var damage := int(Combat.preview_attack(unit, weakest, null)["damage"])
			if damage > top_damage:
				top_damage = damage
				top_id = id
	if top_id != "":
		weights[top_id] = maxf(float(weights[top_id]), ROLE_KEY)
	for unit in loop.get("units", []):
		if Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) == Loop.ROLE_FRIENDLY:
			weights[str(unit["id"])] = 1.0 if board["guarded"].has(str(unit["id"])) else ROLE_FRIENDLY
	return weights


## Value of the board the simulated round left, relative to `before`: battle outcome, party
## deaths (hero / guarded VALUE_GUARDED_DEATH on top), role-weighted HP lost, foe HP lost and
## kills, exposure of every living party unit where it stands (the copy's own threat map),
## units left at or below LOW_HP_RATIO or one worst-case round from death (NEXT_ROUND_DEATH_SHARE),
## a party unit still poisoned priced as the HP its next poison tick takes (VALUE_HP_LOST; its
## one-round-from-death check reads its HP after that tick), the level progress the commandable
## units made (_level_progress, the members below the party's top level weighted up by
## EXP_CATCHUP), the walking distance the hero closed toward a live escape zone
## (VALUE_ESCAPE_STEP), the carried supplies drunk (_supplies_spent), and the candidate's static
## hero_expected_death / hero_can_die (VALUE_HERO_EXPECTED_DEATH / VALUE_HERO_CAN_DIE; the
## latter also when the hero's worst case re-read where the round left him says he can die:
## _reach_can_die). Returns {value, ...terms}.
static func evaluate(before: Dictionary, after: Dictionary, board: Dictionary, candidate: Dictionary, weights: Dictionary) -> Dictionary:
	var out := {"outcome": 0.0, "deaths": 0.0, "hp_lost": 0.0, "enemy": 0.0, "objective": 0.0, "march": 0.0, "threat_removed": 0.0, "exposure": 0.0, "isolation": 0.0, "apart": 0.0, "low_hp": 0.0, "next_round_death": 0.0, "exp": 0.0, "escape": 0.0, "worst_case": 0.0, "poison": 0.0, "supplies": _supplies_spent(before, after, board, candidate)}
	if BattleOutcome.won(after):
		out["outcome"] = VALUE_OUTCOME
	elif BattleOutcome.lost(after):
		out["outcome"] = -VALUE_OUTCOME
	var hero_id := str(board["hero"].get("id", ""))
	var top_level := 1
	for unit in board["commandables"]:
		top_level = maxi(top_level, int(unit.get("level", 1)))
	var saved_cache := _envelope_cache
	_envelope_cache = {}
	var after_board := _board(after)
	var hero_reach_can_die := false
	for unit in before.get("units", []):
		var id := str(unit.get("id", ""))
		var role := str(unit.get("battle_actor_role", ""))
		var later := Loop.unit(after, id)
		if role == Loop.ROLE_ENEMY:
			if not Loop.Presence.living(unit):
				continue
			var lost := float(int(unit["hp"]) - (int(later["hp"]) if Loop.Presence.living(later) else 0)) / maxf(1.0, float(unit["max_hp"]))
			if not Loop.Presence.living(later):
				out["enemy"] += VALUE_ENEMY_KILL + VALUE_ENEMY_HP * lost
				out["threat_removed"] += _threat_removed(before, unit, board, weights)
			else:
				out["enemy"] += VALUE_ENEMY_HP * lost
			if board.get("objectives", []).has(id):
				out["objective"] += VALUE_OBJECTIVE_HP * lost
			continue
		if not weights.has(id) or not Loop.Presence.living(unit):
			continue
		var weight := float(weights[id])
		if not Loop.Presence.living(later):
			out["deaths"] -= weight * VALUE_UNIT_DEATH
			if id == hero_id or board["guarded"].has(id):
				out["deaths"] -= VALUE_GUARDED_DEATH
			continue
		var max_hp := maxf(1.0, float(unit["max_hp"]))
		out["hp_lost"] -= weight * VALUE_HP_LOST * maxf(0.0, float(int(unit["hp"]) - int(later["hp"]))) / max_hp
		if float(later["hp"]) / max_hp <= LOW_HP_RATIO:
			out["low_hp"] -= weight * VALUE_LOW_HP
		var tick := _poison_tick_hp(later, false) if (int(later.get("status_flags", 0)) & Status.POISON) != 0 else 0
		out["poison"] -= weight * VALUE_HP_LOST * float(tick) / max_hp
		if role == Loop.ROLE_PLAYER:
			var threat_ids := _threatening(after, after_board, later, later["coord"])
			var threats := threat_ids.size()
			if threats > 0:
				out["exposure"] -= weight * VALUE_EXPOSURE_HP * minf(_expected_incoming(after, later, threat_ids) / maxf(1.0, float(int(later["hp"]) - tick)), 2.0)
			if threats > 0 and _isolated(after, later):
				out["isolation"] -= weight * VALUE_ISOLATED
			if _escorted(later):
				var gap := float(maxi(0, _party_gap(after, later, later["coord"]) - ISOLATION_DISTANCE))
				out["apart"] -= (VALUE_GUARDED_APART if id != hero_id and board["guarded"].has(id) else weight * VALUE_MEMBER_APART) * gap
			var next_death := threats > 0 and _worst_incoming(after, later, threat_ids) >= int(later["hp"]) - tick
			if next_death:
				out["next_round_death"] -= NEXT_ROUND_DEATH_SHARE * (weight * VALUE_UNIT_DEATH + (VALUE_GUARDED_DEATH if id == hero_id or board["guarded"].has(id) else 0.0))
			elif id == hero_id:
				hero_reach_can_die = _reach_can_die(before, after, later, threat_ids, tick)
			out["exp"] += VALUE_LEVEL_PROGRESS * _level_progress(unit, later) * (1.0 + EXP_CATCHUP * float(maxi(0, top_level - int(unit.get("level", 1)))))
			if id == hero_id and _escape_is_sole_victory(before):
				out["escape"] += VALUE_ESCAPE_STEP * float(_escape_distance(before, unit, unit["coord"]) - _escape_distance(before, unit, later["coord"]))
	_envelope_cache = saved_cache
	for id in board.get("objectives", []):
		var target := Loop.unit(after, str(id))
		if Loop.Presence.living(target):
			out["march"] += VALUE_OBJECTIVE_STEP * (_objective_distance(before, Loop.unit(before, str(id))) - _objective_distance(after, target))
	if bool(candidate.get("hero_expected_death", false)):
		out["worst_case"] = -VALUE_HERO_EXPECTED_DEATH
	elif bool(candidate.get("hero_can_die", false)) or hero_reach_can_die:
		out["worst_case"] = -VALUE_HERO_CAN_DIE
	var value := 0.0
	for key in out:
		out[key] = snappedf(float(out[key]), 0.01)
		value += float(out[key])
	out["value"] = snappedf(value, 0.01)
	return out


## The hero's hero_can_die read again where the simulated round left him (`later`, HP after its
## poison `tick`): the foes whose weapons touch his cell on the simulated board (`threat_ids`)
## plus every foe still living whose move points and longest weapon offset reach that cell from
## where it stood before the round (_reach_bound_ids — a Manhattan bound, no terrain, no bodies),
## critical case included (_worst_incoming). The candidate's own hero_can_die comes from the
## static threat map, which floods every foe around the hero's own body where he stands: level
## 52, seed 3 round 8, 雷歐納德 at 13/35 beside enemy021_1 retreated five cells to (2,30), read
## there by nobody because his body at (6,31) blocked the 021's way west; the 021 walked through
## it and struck him dead with a 16-point critical (plain preview 12 < 13, so the simulated
## board's plain next-round check passed him too).
static func _reach_can_die(before: Dictionary, after: Dictionary, later: Dictionary, threat_ids: Array, tick: int) -> bool:
	var ids := threat_ids.duplicate()
	for id in _reach_bound_ids(before, after, later, later["coord"]):
		if not ids.has(id):
			ids.append(id)
	return not ids.is_empty() and _worst_incoming(after, later, ids, true) >= int(later["hp"]) - tick


## Foes living in `after` whose weapon could touch `unit` on `cell` from where they stood in
## `before`: the threat map's own Manhattan pre-filter (_threat_reach), without the flood.
static func _reach_bound_ids(before: Dictionary, after: Dictionary, unit: Dictionary, cell: Vector2i) -> Array:
	var out: Array = []
	var points: Array = Loop.Footprint.cells(unit, cell)
	for foe in before.get("units", []):
		if str(foe.get("battle_actor_role", "")) != Loop.ROLE_ENEMY or not Loop.Presence.living(foe) or bool(foe.get("no_attack", false)):
			continue
		if not Loop.Presence.living(Loop.unit(after, str(foe["id"]))):
			continue
		var pattern := Loop.weapon_pattern(before, foe)
		if not bool(pattern.get("ok", false)):
			continue
		var reach := _threat_reach(foe, pattern["offsets"])
		var coord: Vector2i = foe["coord"]
		for point in points:
			if absi(point.x - coord.x) + absi(point.y - coord.y) <= reach:
				out.append(str(foe["id"]))
				break
	return out


## Levels of progress from `before` to `later` (the same unit): levels gained plus the change in
## its experience as a share of ProgressionRules.exp_to_next at its level.
static func _level_progress(before: Dictionary, later: Dictionary) -> float:
	var level_before := int(before.get("level", 1))
	var level_after := int(later.get("level", 1))
	var share_before := float(int(before.get("exp", 0))) / float(maxi(1, Progression.exp_to_next(level_before)))
	var share_after := float(int(later.get("exp", 0))) / float(maxi(1, Progression.exp_to_next(level_after)))
	return maxf(0.0, float(level_after - level_before) + share_after - share_before)


## Potion economy: the price of the healing / poison-curing consumables (_is_supply) the
## commandable party's bags lost in the simulated round. The bags go with the campaign carry, so
## a potion drunk here is missing in every later battle up to the next shop; each one costs
## VALUE_SUPPLY / (1 + supplies the party still holds after it) — cheap from a full stock,
## dear for the last one, so the HP a plan must save to justify a drink rises as the stock falls
## (level 51, chapter walk: 雷歐納德 at full HP fed two of his three 回復藥 to a 024 guest for
## 5 and 20 points of value, and entered level 52 alone against 皇帝 with one).
## The hero's own drink from at or below LOW_HP_RATIO (_low_hero_drink) costs VALUE_LOW_HERO_DRINK
## instead: the valuation has no term for HP restored, so out of every foe's reach the drink only
## lifted VALUE_LOW_HP against a VALUE_SUPPLY / 2 price and a safe low hero never drank (level 52,
## chapter hand-off with the REWARD settlement: 雷歐納德 at 11/39 and at 3/35 held the line ten and
## thirteen rounds while 皇帝 wore the 024 guest down, drank only when he was next, and fell one
## on one, seeds 1 and 2). Every other drink in the round keeps its stock price.
static func _supplies_spent(before: Dictionary, after: Dictionary, board: Dictionary, candidate: Dictionary = {}) -> float:
	var held_before := 0
	var held_after := 0
	for unit in board["commandables"]:
		var id := str(unit["id"])
		var bag_before: Variant = Loop.unit(before, id).get("inventory", [])
		var bag_after: Variant = Loop.unit(after, id).get("inventory", [])
		held_before += _supply_count(before, bag_before) if bag_before is Array else 0
		held_after += _supply_count(after, bag_after) if bag_after is Array else 0
	var spent_count := maxi(0, held_before - held_after)
	var cost := 0.0
	if spent_count > 0 and _low_hero_drink(board, candidate):
		spent_count -= 1
		cost += VALUE_LOW_HERO_DRINK
	for spent in range(spent_count):
		cost += VALUE_SUPPLY / float(1 + held_after + spent)
	return -cost


## True when `candidate` is the hero drinking a healing item on himself from at or below
## LOW_HP_RATIO (the heal plan's own healer, target and HP ratio before the drink).
static func _low_hero_drink(board: Dictionary, candidate: Dictionary) -> bool:
	var hero_id := str(board["hero"].get("id", ""))
	return hero_id != "" and str(candidate.get("kind", "")) == "heal" and bool(candidate.get("heal_target_is_hero", false)) and str(candidate.get("healer_id", "")) == hero_id and float(candidate.get("heal_target_hp_ratio", 1.0)) <= LOW_HP_RATIO


## Value of a foe the simulated round killed as the damage it will not deal: its hardest expected
## strike on a living commandable unit (_expected_strike: preview × hit rate), as a share of that
## unit's max HP, over THREAT_ROUNDS rounds, priced like HP lost (VALUE_HP_LOST × role weight).
## A kill ends a foe's strikes for the rest of the battle, which VALUE_ENEMY_KILL alone did not
## weigh against the round's HP lost (level 5, chapter hand-off with the con growth: every
## round the holds that walked out of reach outvalued the focus plans, the party dealt one kill
## in eight rounds and was run down in the corner). Not while escaping is the sole victory: the
## runner leaves the foes behind and the escape term decides (level 53 hand-off, seed 2: won
## by running without it, lost fighting the gate guards with it).
static func _threat_removed(before: Dictionary, foe: Dictionary, board: Dictionary, weights: Dictionary) -> float:
	if bool(foe.get("no_attack", false)) or _escape_is_sole_victory(before):
		return 0.0
	var best := 0.0
	for unit in board["commandables"]:
		var victim := Loop.unit(before, str(unit["id"]))
		if not Loop.Presence.living(victim):
			continue
		var share := _expected_strike(foe, victim) / maxf(1.0, float(victim["max_hp"]))
		best = maxf(best, share * float(weights.get(str(victim["id"]), ROLE_OTHER)))
	return VALUE_HP_LOST * THREAT_ROUNDS * minf(best, 1.0)


## Mean walking distance (_march_distance) from the living commandable party units of `loop` to
## objective target `target`; units with no route are left out; 0.0 when none is left.
static func _objective_distance(loop: Dictionary, target: Dictionary) -> float:
	var total := 0.0
	var count := 0
	for unit in loop.get("units", []):
		if Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) == Loop.ROLE_PLAYER and bool(unit.get("player_commandable", false)):
			var distance := _march_distance(loop, unit, unit["coord"], target)
			if distance < ESCAPE_UNREACHABLE:
				total += float(distance)
				count += 1
	return total / float(count) if count > 0 else 0.0


# ----------------------------------------------------------------------------- skill forecasts (pure)

## Every commandable unit's affordable magic / special options (BattlePlayLoop.magic_options /
## special_options, quote ok) whose damage policy the forecaster covers: [{unit, option, descriptor}].
static func _skill_options(loop: Dictionary, unit: Dictionary) -> Array:
	var out: Array = []
	var options: Array = Loop.magic_options(loop, str(unit["id"]))
	options.append_array(Loop.special_options(loop, str(unit["id"])))
	for option in options:
		if not bool(option["quote"].get("ok", false)):
			continue
		var descriptor: Dictionary = loop["skill_book"]["skills"][str(option["id"])]
		if str(descriptor.get("damage_policy", "")) not in FORECAST_POLICIES:
			continue
		out.append({"unit": unit, "option": option, "descriptor": descriptor})
	return out


## Best forecast cast per (caster, skill, center target) over every commandable unit, best
## value first. Each intent: {caster_id, skill_id, skill_name, channel, target_id, cast_center,
## cell, expected_damage, kills, heal_hp, targets_hit, resource, cost, resource_after, value}.
static func _skill_intents(loop: Dictionary, board: Dictionary) -> Array:
	var best := {}
	for unit in board["commandables"]:
		for row in _skill_options(loop, unit):
			for intent in _cast_intents(loop, board, unit, row["option"], row["descriptor"]):
				var key := "%s|%s|%s" % [str(intent["caster_id"]), str(intent["skill_id"]), str(intent["target_id"])]
				if not best.has(key) or _intent_before(intent, best[key]):
					best[key] = intent
	var out: Array = best.values()
	out.sort_custom(_intent_before)
	return out


## Higher forecast value first; ties: fewer foes threatening the cast cell, then shorter path.
static func _intent_before(a: Dictionary, b: Dictionary) -> bool:
	if float(a["value"]) != float(b["value"]):
		return float(a["value"]) > float(b["value"])
	if int(a["threats"]) != int(b["threats"]):
		return int(a["threats"]) < int(b["threats"])
	if int(a["path_cost"]) != int(b["path_cost"]):
		return int(a["path_cost"]) < int(b["path_cost"])
	return str(a["skill_id"]) + str(a["target_id"]) < str(b["skill_id"]) + str(b["target_id"])


## Every castable (cell, center) of one skill for `unit` this round with its forecast; casts
## whose forecast neither damages nor heals are dropped. Geometry is SkillTargetRules' own
## (cells / candidate_centers), the center unit AISkillPlanning.target_for_center's, and
## legality SkillResolutionRules.prepare_cast's — the same calls the AI planner and the
## loop's attack_target make.
static func _cast_intents(loop: Dictionary, board: Dictionary, unit: Dictionary, option: Dictionary, descriptor: Dictionary) -> Array:
	var skill_id := str(option["id"])
	var channel := str(descriptor["channel"])
	var fields: Dictionary = option["fields"]
	var targeting: Dictionary = loop["skill_target_data"]
	var quote: Dictionary = option["quote"]
	var out: Array = []
	for cell in _reachable(loop, unit):
		if Position.cast_error(unit, loop["skill_book"], loop["equipment_items"], channel, cell != unit["coord"]) != "":
			continue
		var cast_cells: Array = SkillTargets.cells(cell, fields, targeting, loop["map_size"])
		if cast_cells.is_empty():
			continue
		for center in SkillTargets.candidate_centers(unit, loop["units"], fields, targeting, loop["map_size"], cell):
			if not cast_cells.has(center):
				continue
			var target := SkillPlanning.target_for_center(unit, loop["units"], fields, targeting, loop["map_size"], cell, center)
			if target.is_empty():
				continue
			var ready := SkillResolution.prepare_cast(unit, target, loop["units"], skill_id, fields, loop["skill_book"], targeting, loop["equipment_items"], cell, loop["map_size"], center)
			if not bool(ready.get("ok", false)):
				continue
			var forecast := _forecast_cast(loop, unit, ready, descriptor)
			if float(forecast["expected_damage"]) <= 0.0 and int(forecast["heal_hp"]) <= 0:
				continue
			var value := float(forecast["expected_damage"]) + WEIGHT_KILL * float(forecast["kills"]) + WEIGHT_HEAL * float(forecast["heal_hp"]) - _cost_penalty(str(quote["resource"]), int(quote["amount"]))
			var intent := {"caster_id": str(unit["id"]), "skill_id": skill_id, "skill_name": str(option["name"]), "channel": channel, "target_id": str(target["id"]),
				"cast_center": center, "cell": cell, "resource": str(quote["resource"]), "cost": int(quote["amount"]), "resource_after": int(quote["after"]),
				"value": snappedf(value, 0.01), "threats": _threatening(loop, board, unit, cell).size(), "path_cost": _path_cost(loop, unit, cell)}
			intent.merge(forecast, true)
			out.append(intent)
	return out


## Numbers of a prepared cast: per target the rules' own roll evaluated with _forecast_draws
## (hit check passed, midpoint draws) times its hit rate, capped by the target's HP;
## healing through SupportMagicRules.resolve the same way. A healing cast only counts a
## target at or below HEAL_RATIO (the item heal's bar).
static func _forecast_cast(loop: Dictionary, caster: Dictionary, ready: Dictionary, descriptor: Dictionary) -> Dictionary:
	var damage := 0.0
	var kills := 0
	var heal := 0
	var hit := 0
	var by_target := {}
	var pulses := Repeated.PULSES if str(descriptor["damage_policy"]) == "native_special_sequence" else 1
	for index in range(ready["targets"].size()):
		var target: Dictionary = ready["targets"][index]
		var prepared: Dictionary = ready["prepared"][index]
		if prepared.has("support"):
			if float(target["hp"]) / maxf(1.0, float(target["max_hp"])) > HEAL_RATIO:
				continue
			var resolved := Support.resolve(prepared["support"], target, int(caster["hit_bonus_accum"]), _forecast_draws(), loop["equipment_items"])
			if int(resolved["healing"]) > 0:
				heal += int(resolved["healing"])
				hit += 1
			continue
		var roll := {}
		if prepared.has("special"):
			roll = SpecialDamage.roll(prepared["special"]["input"], _forecast_draws())
		elif prepared.has("arrow"):
			roll = PoisonArrow.roll(prepared["arrow"]["input"], _forecast_draws())
		elif prepared.has("status") and (int(prepared["status"]["function_mask"]) & 1) != 0:
			var input: Dictionary = prepared["status"]["roll_input"].duplicate(true)
			input["proc"] = 0
			roll = PoisonArrow.roll(input, _forecast_draws()) if str(descriptor["channel"]) == "special" else MagicRolls.roll(input, _forecast_draws())
		if roll.is_empty():
			continue
		var rate := clampi(int(roll["hit_rate"]), 0, 100)
		var expected := minf(float(target["hp"]), float(int(roll["value"]) * pulses) * float(rate) / 100.0)
		if expected <= 0.0:
			continue
		damage += expected
		by_target[str(target["id"])] = float(by_target.get(str(target["id"]), 0.0)) + expected
		hit += 1
		if expected >= float(target["hp"]):
			kills += 1
	return {"expected_damage": snappedf(damage, 0.1), "kills": kills, "heal_hp": heal, "targets_hit": hit, "damage_by_target": by_target}


## Deterministic draw source for one roll: the first draw (every roll's hit check) is 0 so
## the value path runs; each later draw is the midpoint the rules use for a null-RNG preview.
static func _forecast_draws() -> Callable:
	var count := [0]
	return func(bound: int) -> int:
		count[0] += 1
		return 0 if count[0] == 1 else bound / 2


## The planned skill's best cast at `target_id` for `unit` now (re-evaluated at grounding time),
## from `cell` when that cast is still possible (the attack-cell assignment's cell); {} when none.
static func _planned_cast(loop: Dictionary, board: Dictionary, unit: Dictionary, skill_id: String, target_id: String, cell: Variant = null) -> Dictionary:
	for row in _skill_options(loop, unit):
		if str(row["option"]["id"]) != skill_id:
			continue
		var best := {}
		var from_cell := {}
		for intent in _cast_intents(loop, board, unit, row["option"], row["descriptor"]):
			if str(intent["target_id"]) != target_id:
				continue
			if best.is_empty() or _intent_before(intent, best):
				best = intent
			if cell is Vector2i and intent["cell"] == cell and (from_cell.is_empty() or _intent_before(intent, from_cell)):
				from_cell = intent
		return best if from_cell.is_empty() else from_cell
	return {}


# ----------------------------------------------------------------------------- intents (pure)

## Reachable cells for `unit` this round including where it stands (only when it may still move).
static func _reachable(loop: Dictionary, unit: Dictionary) -> Array:
	var cells: Array = [unit["coord"]]
	if str(unit["id"]) == str(loop.get("selected_unit_id", "")) and bool(loop.get("moved_this_action", false)):
		return cells
	for cell in _movement_cells(loop, str(unit["id"])):
		if cell != unit["coord"]:
			cells.append(cell)
	return cells


## Movement envelopes memoized for one take_player_action call (the loop is immutable
## until a command is issued, and every command returns a new dictionary): the planner's
## candidate × unit × foe reach queries otherwise recompute the same envelope thousands of
## times on a 39-actor field (level 12: 170 s a battle before, see the brain comparison).
## One entry per unit ("envelope:<id>", BattlePlayLoop._movement_envelope): its reachable
## cells and every path size are read from that one flood — Loop.movement_cells and
## Loop.movement_path each flood the same envelope, so a per-cell path query cost a whole
## flood (S13: 386 floods of one level-44 decision's hold_line search).
static var _envelope_cache: Dictionary = {}
## True while the lookahead mode plans or grounds: the shared cell searches then also prefer
## strike cells the target cannot retaliate from (range first strike). Scored is unchanged.
static var _tactics: bool = false


static func _movement_envelope(loop: Dictionary, unit_id: String) -> Dictionary:
	var key := "envelope:" + unit_id
	if not _envelope_cache.has(key):
		_envelope_cache[key] = Loop._movement_envelope(loop, unit_id)
	return _envelope_cache[key]


## Loop.movement_cells over the memoized envelope.
static func _movement_cells(loop: Dictionary, unit_id: String) -> Array:
	return _movement_envelope(loop, unit_id).get("reachable_coords", [])


## Loop.movement_path(...).size() over the memoized envelope.
static func _movement_path_size(loop: Dictionary, unit_id: String, cell: Vector2i) -> int:
	return (_movement_envelope(loop, unit_id).get("reachable_by_coord", {}).get(cell, {}).get("path", []) as Array).size()


## Cells among `_reachable` from which `unit`'s weapon touches `foe`.
static func _strike_cells(loop: Dictionary, unit: Dictionary, foe: Dictionary) -> Array:
	if bool(unit.get("no_attack", false)):
		return []
	var pattern := Loop.weapon_pattern(loop, unit)
	if not bool(pattern.get("ok", false)):
		return []
	var reachable := {}
	for cell in _reachable(loop, unit):
		reachable[cell] = true
	var out: Array = []
	var seen := {}
	for point in Loop.Footprint.cells(foe):
		for offset in pattern["offsets"]:
			var cell: Vector2i = point - Vector2i(int(offset[0]), int(offset[1]))
			if reachable.has(cell) and not seen.has(cell):
				seen[cell] = true
				out.append(cell)
	return out


## Least-threatened strike cell against `foe` (ties: shortest path, then staying put); null when
## none. Under _tactics a cell the target's own weapon cannot reach from where it stands (no
## counter) comes before one it can.
static func _focus_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, foe: Dictionary) -> Variant:
	var best: Variant = null
	var best_key: Array = []
	var retaliation: Array = _retaliation_cells(loop, foe) if _tactics else []
	for cell in _strike_cells(loop, unit, foe):
		var key := [_threatening(loop, board, unit, cell).size(), 1 if _tactics and Loop.Footprint.overlaps(unit, retaliation, cell) else 0, _path_cost(loop, unit, cell)]
		if best == null or key < best_key:
			best = cell
			best_key = key
	return best


## Cells `foe`'s weapon touches from where it stands (its counter reach); [] when it cannot strike.
static func _retaliation_cells(loop: Dictionary, foe: Dictionary) -> Array:
	if bool(foe.get("no_attack", false)):
		return []
	var pattern := Loop.weapon_pattern(loop, foe)
	if not bool(pattern.get("ok", false)):
		return []
	return Loop.TacticalGridRules.attack_pattern_cells(foe["coord"], pattern["offsets"], loop["map_size"])


static func _path_cost(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> int:
	if cell == unit["coord"]:
		return 0
	return _movement_path_size(loop, str(unit["id"]), cell)


## Reachable cell with the fewest threatening foes, then least expected incoming damage,
## then farthest from the nearest foe.
static func _safest_cell(loop: Dictionary, board: Dictionary, unit: Dictionary) -> Vector2i:
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		var ids := _threatening(loop, board, unit, cell)
		var key := [ids.size(), 1 if _isolated_at(loop, unit, cell) else 0, _expected_incoming(loop, unit, ids), -_nearest_foe_distance(unit, cell, board["enemies"])]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


## Weakest foe `unit` touches from `cell`: {foe_id, expected_damage, kills}; {} when none.
static func _best_strike_from(loop: Dictionary, unit: Dictionary, cell: Vector2i) -> Dictionary:
	if bool(unit.get("no_attack", false)):
		return {}
	var pattern := Loop.weapon_pattern(loop, unit)
	if not bool(pattern.get("ok", false)):
		return {}
	var cells: Array = Loop.TacticalGridRules.attack_pattern_cells(cell, pattern["offsets"], loop["map_size"])
	var best := {}
	for foe in _living_foes(loop, unit):
		if Loop.Footprint.contact(foe, cells) == null:
			continue
		var distance := Loop.Footprint.distance(unit, foe, cell)
		if best.is_empty() or int(foe["hp"]) < int(best["hp"]) or (int(foe["hp"]) == int(best["hp"]) and distance < int(best["distance"])):
			var expected := _expected_strike(unit, foe)
			best = {"foe_id": str(foe["id"]), "hp": int(foe["hp"]), "distance": distance, "expected_damage": expected, "kills": 1 if expected >= float(foe["hp"]) else 0}
	return best


static func _best_strike_in_place(loop: Dictionary, unit: Dictionary) -> Dictionary:
	return _best_strike_from(loop, unit, unit["coord"])


## Greedy intent for one unit: strike the weakest foe reachable this round from the
## least-threatened strike cell, else move to the reachable cell nearest `toward` (or the
## nearest foe) and strike whatever is in range there. Returns {cell, expected_damage, kills}.
## Under _tactics a step that would leave the unit where REACH_LIMIT or more surviving foes
## can strike it is replaced by holding one cell outside their reach (_hold_cell), striking
## from there when anything is in range — the reach rule applied while a plan is composed, so
## a heal or cast plan is not thrown out for the greedy steps of the units around it.
static func _greedy_intent(loop: Dictionary, board: Dictionary, unit: Dictionary, approach_only: bool, toward: Dictionary = {}) -> Dictionary:
	var foes := _living_foes(loop, unit)
	var step := {}
	if not approach_only:
		var target := {}
		var target_cell: Variant = null
		for foe in foes:
			var cell: Variant = _focus_cell(loop, board, unit, foe)
			if cell == null:
				continue
			if target.is_empty() or int(foe["hp"]) < int(target["hp"]) or (int(foe["hp"]) == int(target["hp"]) and _path_cost(loop, unit, cell) < _path_cost(loop, unit, target_cell)):
				target = foe
				target_cell = cell
		if not target.is_empty():
			var expected := _expected_strike(unit, target)
			step = {"cell": target_cell, "foe_id": str(target["id"]), "expected_damage": expected, "kills": 1 if expected >= float(target["hp"]) else 0}
	if step.is_empty():
		var goal := toward if not toward.is_empty() else {}
		var cell: Vector2i = _approach_cell(loop, board, unit, goal, foes)
		var strike := _best_strike_from(loop, unit, cell)
		step = {"cell": cell, "foe_id": str(strike.get("foe_id", "")), "expected_damage": float(strike.get("expected_damage", 0.0)), "kills": int(strike.get("kills", 0))}
	if _tactics and _exposed(loop, board, unit, step["cell"], str(step["foe_id"]) if int(step["kills"]) > 0 else ""):
		var safe := _hold_cell(loop, board, unit, [])
		if safe != step["cell"]:
			var strike := _best_strike_from(loop, unit, safe)
			step = {"cell": safe, "foe_id": str(strike.get("foe_id", "")), "expected_damage": float(strike.get("expected_damage", 0.0)), "kills": int(strike.get("kills", 0)), "held": true}
	return step


## True when REACH_LIMIT or more foes other than `killed_id` can strike `unit` at `cell` and
## their worst blows together would kill it (the reach rule's cell test).
static func _exposed(loop: Dictionary, board: Dictionary, unit: Dictionary, cell: Vector2i, killed_id: String) -> bool:
	var ids := _threatening(loop, board, unit, cell)
	if killed_id != "":
		ids.erase(killed_id)
	return ids.size() >= REACH_LIMIT and _worst_incoming(loop, unit, ids) >= int(unit.get("hp", 0))


## Reachable cell nearest to `goal` (or to the nearest of `foes`); ties: fewer threats for
## the hero and guarded units, then staying put.
static func _approach_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, goal: Dictionary, foes: Array) -> Vector2i:
	var careful: bool = str(unit["id"]) == str(board["hero"].get("id", "")) or board["guarded"].has(str(unit["id"]))
	var best: Vector2i = unit["coord"]
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		var distance := Loop.Footprint.distance(unit, goal, cell) if not goal.is_empty() else _nearest_foe_distance(unit, cell, foes)
		var key := [distance, _threatening(loop, board, unit, cell).size() if careful else 0, 0 if cell == unit["coord"] else 1]
		if best_key.is_empty() or key < best_key:
			best = cell
			best_key = key
	return best


static func _nearest_foe_distance(unit: Dictionary, origin: Vector2i, foes: Array) -> int:
	var best := -1
	for foe in foes:
		var distance := Loop.Footprint.distance(unit, foe, origin)
		if best < 0 or distance < best:
			best = distance
	return best if best >= 0 else 0


## {healer_id, target_id, item_code, slot, cell, heal_hp} for the lowest-HP player-side unit
## (at or below HEAL_RATIO) some commandable unit with a healing item can stand next to; {}
## when none. Item use is the loop's own `use_item` (IMPLEMENTED_COMMANDS "item"). Only a
## healer still to act this round (_pending_ids) is offered: a plan made mid-round for a healer
## that has acted cannot be grounded (level 3 round 5: the only heal offered named the hero,
## who had acted; 緹娜, 14 HP with her own potion, was never offered as her own healer).
## Ties on the target go to the target itself (no move), then the earlier-listed healer.
## The healer is the holder whose turn comes first in the speed queue (level 6, chapter hand-off:
## 雷歐納德 at 20/41 with his own 回復藥 was left to heal himself on his turn — the two guards that
## move before him struck him dead for 18 + 15 while 琥, acting first with 回復藥 in his bag,
## attacked; the self-heal preference this replaced read the queue as if every unit acted at once).
static func _heal_intent(loop: Dictionary, board: Dictionary, protected_only: bool = false) -> Dictionary:
	var best := {}
	var pending := _pending_ids(loop)
	var protected: Array = board["guarded"].duplicate()
	if not board["hero"].is_empty():
		protected.append(str(board["hero"]["id"]))
	for unit in board["commandables"]:
		if not unit.get("inventory") is Array or not pending.has(str(unit["id"])):
			continue
		var healing := ItemUse.first_healing_slot(unit["inventory"], loop["consumables"])
		if not bool(healing.get("ok", false)) or int(healing["index"]) < 0:
			continue
		var slot := int(healing["index"])
		var code := str(int(unit["inventory"][slot]))
		var definition: Dictionary = loop["consumables"][code]
		for target in loop["units"]:
			if not Loop.Presence.living(target) or str(target.get("battle_actor_role", "")) not in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]:
				continue
			if protected_only and not protected.has(str(target["id"])):
				continue
			var ratio := float(target["hp"]) / maxf(1.0, float(target["max_hp"]))
			if ratio > HEAL_RATIO and not _in_kill_range(loop, board, target, pending):
				continue
			var effect := ItemUse.prepare(target, definition)
			if not bool(effect.get("ok", false)) or int(effect.get("restored_hp", 0)) <= 0:
				continue
			var cell: Variant = _adjacent_cell(loop, board, unit, target)
			if cell == null:
				continue
			var self_heal := str(unit["id"]) == str(target["id"])
			var turn := pending.find(str(unit["id"]))
			if best.is_empty() or ratio < float(best["ratio"]) or (ratio == float(best["ratio"]) and turn < int(best["turn"])):
				best = {"healer_id": str(unit["id"]), "target_id": str(target["id"]), "item_code": code, "slot": slot, "cell": cell, "heal_hp": int(effect["restored_hp"]), "ratio": ratio, "self_heal": self_heal, "turn": turn}
	return best


## True when the foes whose weapons touch `unit` where it stands would kill it if every strike
## landed (plain worst case, after its own poison tick when it is poisoned and still to act):
## a player drinks before that round, whatever the HP bar says (level 5, chapter hand-off:
## 緹娜 at 23/37 — above HEAL_RATIO — stood six rounds beside a 038 that strikes for 23, with
## four 回復藥 in her bag, and fell to it).
static func _in_kill_range(loop: Dictionary, board: Dictionary, unit: Dictionary, pending: Array) -> bool:
	var ids := _threatening(loop, board, unit, unit["coord"])
	if ids.is_empty():
		return false
	return _worst_incoming(loop, unit, ids) >= int(unit.get("hp", 0)) - _poison_tick(unit, pending, [], false)


## Least-threatened reachable cell from which `unit` is within item range (distance ≤ 1) of `target`.
static func _adjacent_cell(loop: Dictionary, board: Dictionary, unit: Dictionary, target: Dictionary) -> Variant:
	var best: Variant = null
	var best_key: Array = []
	for cell in _reachable(loop, unit):
		if str(unit["id"]) != str(target["id"]) and Loop.Footprint.distance(unit, target, cell) > 1:
			continue
		var key := [_threatening(loop, board, unit, cell).size(), _path_cost(loop, unit, cell)]
		if best == null or key < best_key:
			best = cell
			best_key = key
	return best


static func _living_foes(loop: Dictionary, actor: Dictionary) -> Array:
	var player_side := str(actor.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]
	var out: Array = []
	for unit in loop.get("units", []):
		if not Loop.Presence.living(unit) or str(unit.get("id", "")) == str(actor.get("id", "")):
			continue
		var unit_player_side := str(unit.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]
		if unit_player_side != player_side:
			out.append(unit)
	return out


# ----------------------------------------------------------------------------- grounding (commands)

## Grounds the round's plan for the selected unit through the public command entry points.
static func _ground(loop: Dictionary, id: String, plan: Dictionary, rng: Variant) -> Dictionary:
	var board := _board(loop)
	var unit := Loop.unit(loop, id)
	var is_hero := id == str(board["hero"].get("id", ""))
	match str(plan.get("kind", "advance")):
		"rescue":
			if is_hero:
				return _move_then_strike(loop, id, _safest_cell(loop, board, unit), "", rng)
			var pursuer := Loop.unit(loop, str(plan["target_id"]))
			if Loop.Presence.living(pursuer):
				var strike_cell: Variant = _focus_cell(loop, board, unit, pursuer)
				if strike_cell is Vector2i and not _exposed(loop, board, unit, strike_cell, str(pursuer["id"])):
					var stand_at := _guarded_cell(loop, board, unit, strike_cell)
					return _move_then_strike(loop, id, stand_at, str(pursuer["id"]) if stand_at == strike_cell else "", rng)
				var closing := _greedy_intent(loop, board, unit, true, pursuer)
				return _move_then_strike(loop, id, _guarded_cell(loop, board, unit, closing["cell"]), "", rng)
		"focus":
			var foe := Loop.unit(loop, str(plan["target_id"]))
			if Loop.Presence.living(foe):
				var cell: Variant = _focus_cell(loop, board, unit, foe)
				if cell is Vector2i and _tactics and _exposed(loop, board, unit, cell, str(foe["id"])):
					cell = null
				if cell is Vector2i:
					var stand := _guarded_cell(loop, board, unit, cell)
					return _move_then_strike(loop, id, stand, str(foe["id"]) if stand == cell else "", rng)
				var approach := _greedy_intent(loop, board, unit, true, foe)
				return _move_then_strike(loop, id, _guarded_cell(loop, board, unit, approach["cell"]), "", rng)
		"objective":
			var target := Loop.unit(loop, str(plan["target_id"]))
			if Loop.Presence.living(target):
				var blow := _objective_step(loop, board, unit, target, _strike_assignment(loop, board, target))
				if not (blow["cast"] as Dictionary).is_empty():
					var cast := _cast(loop, id, {"skill_id": str(blow["cast"]["skill_id"]), "target_id": str(target["id"]), "cell": blow["cell"]}, board, rng)
					if not cast.is_empty():
						return cast
				return _move_then_strike(loop, id, blow["cell"], str(blow["foe_id"]), rng)
		"escort":
			var guard := Loop.unit(loop, str(plan["target_id"]))
			if _escorted(guard):
				var goal: Variant = _planned_cell(plan, str(guard["id"])) if _pending_ids(loop).has(str(guard["id"])) else null
				var walk := _escort_step(loop, board, unit, guard, goal)
				return _move_then_strike(loop, id, walk["cell"], str(walk["foe_id"]), rng)
		"protect_hero":
			if is_hero:
				return _move_then_strike(loop, id, _safest_cell(loop, board, unit), "", rng)
		"hold_line", "bait", "formation":
			var planned: Variant = _planned_cell(plan, id)
			var cell: Vector2i = planned if planned is Vector2i and (planned == unit["coord"] or _reachable(loop, unit).has(planned)) else _safest_cell(loop, board, unit)
			return _move_then_strike(loop, id, _guarded_cell(loop, board, unit, cell), "", rng)
		"escape":
			if is_hero and str(loop.get("objective_phase", "")) == "escape" and not loop.get("escape_zone", []).is_empty():
				var cell := _escape_cell(loop, board, unit)
				var strike := _escape_strike(loop, unit, cell)
				if strike.is_empty():
					return _move_then_wait(loop, id, cell)
				return _move_then_strike(loop, id, cell, str(strike["foe_id"]), rng)
		"heal", "cure":
			if id == str(plan.get("healer_id", "")):
				var healed := _heal(loop, id, plan, board)
				if not healed.is_empty():
					return healed
		"magic", "special":
			if id == str(plan.get("caster_id", "")):
				var cast := _cast(loop, id, plan, board, rng)
				if not cast.is_empty():
					return cast
	var step := _greedy_intent(loop, board, unit, false)
	var stand := _guarded_cell(loop, board, unit, step["cell"])
	return _move_then_strike(loop, id, stand, str(step.get("foe_id", "")) if stand == step["cell"] else "", rng)


## Moves to `cell` when it differs from the unit's cell, then strikes `foe_id` (or the weakest
## foe in range when ""), else waits.
static func _move_then_strike(loop: Dictionary, id: String, cell: Vector2i, foe_id: String, rng: Variant) -> Dictionary:
	var next := loop
	var moved := false
	var unit := Loop.unit(next, id)
	if cell != unit["coord"] and Loop.command_available(next, "move"):
		var moving := Loop.move_unit_to(Loop.choose_command(next, "move"), cell)
		if bool(moving.get("moved_this_action", false)):
			next = moving
			moved = true
		else:
			next = Loop.cancel_interaction(moving)
	return _strike_or_wait(next, id, foe_id, rng, moved)


## Moves to `cell` when it differs from the unit's cell, then waits without striking.
static func _move_then_wait(loop: Dictionary, id: String, cell: Vector2i) -> Dictionary:
	var next := loop
	var moved := false
	var unit := Loop.unit(next, id)
	if cell != unit["coord"] and Loop.command_available(next, "move"):
		var moving := Loop.move_unit_to(Loop.choose_command(next, "move"), cell)
		if bool(moving.get("moved_this_action", false)):
			next = moving
			moved = true
		else:
			next = Loop.cancel_interaction(moving)
	if BattleOutcome.decided(next):
		return {"loop": next, "action": "move"}
	var waited := Loop.choose_command(next, "wait")
	if Loop.same_state(waited, next):
		return {"loop": next, "action": ""}
	return {"loop": waited, "action": "move" if moved else "wait"}


static func _strike_or_wait(loop: Dictionary, id: String, foe_id: String, rng: Variant, moved: bool) -> Dictionary:
	if Loop.command_available(loop, "attack"):
		var struck := _try_attack(loop, id, foe_id, rng)
		if not struck.is_empty():
			return {"loop": struck, "action": "move_then_attack" if moved else "attack"}
	var waited := Loop.choose_command(loop, "wait")
	if Loop.same_state(waited, loop):
		return {"loop": loop, "action": ""}
	return {"loop": waited, "action": "move" if moved else "wait"}


## Strikes `foe_id` when it is in range, else the weakest foe in range; {} when none.
static func _try_attack(loop: Dictionary, id: String, foe_id: String, _rng: Variant) -> Dictionary:
	var unit := Loop.unit(loop, id)
	var cells: Array = Loop.attack_cells(loop, id)
	var target := ""
	if foe_id != "":
		var foe := Loop.unit(loop, foe_id)
		if Loop.Presence.living(foe) and Loop.Footprint.contact(foe, cells) != null:
			target = foe_id
	if target == "":
		target = str(_best_strike_in_place(loop, unit).get("foe_id", ""))
	if target == "":
		return {}
	# Settlement draws from the loop's damage stream (DamageRandomStream), as the product does.
	var struck := Loop.attack_target(Loop.choose_command(loop, "attack"), target)
	if BattleOutcome.decided(struck):
		return struck
	if not bool(struck.get("attacked_this_action", false)):
		return {}
	if Loop.loot_waiting(struck):
		return struck
	return Loop.finish_exhausted_action(struck)


## Moves the caster to its cast cell and casts the planned skill at the planned target through
## choose_command("magic" | "special") / choose_magic / choose_special / attack_target; {} when
## the plan no longer applies before anything was committed. Once the caster has moved, a cast
## the loop refuses falls back to a weapon strike or wait from the new cell.
static func _cast(loop: Dictionary, id: String, plan: Dictionary, board: Dictionary, rng: Variant) -> Dictionary:
	var unit := Loop.unit(loop, id)
	var skill_id := str(plan["skill_id"])
	var target_id := str(plan["target_id"])
	if not Loop.Presence.living(Loop.unit(loop, target_id)):
		return {}
	var intent := _planned_cast(loop, board, unit, skill_id, target_id, plan.get("cell"))
	if intent.is_empty():
		return {}
	var channel := str(intent["channel"])
	var next := loop
	var moved := false
	if intent["cell"] != unit["coord"]:
		if not Loop.command_available(next, "move"):
			return {}
		var moving := Loop.move_unit_to(Loop.choose_command(next, "move"), intent["cell"])
		if not bool(moving.get("moved_this_action", false)):
			return {}
		next = moving
		moved = true
	var action := ("move_then_%s" % channel) if moved else channel
	if not Loop.command_available(next, channel):
		return _strike_or_wait(next, id, "", rng, moved) if moved else {}
	var selecting := Loop.choose_command(next, channel)
	if channel == "magic":
		selecting = Loop.choose_magic(selecting, skill_id)
	elif str(selecting.get("interaction", "")) == "special_select":
		selecting = Loop.choose_special(selecting, skill_id)
	if str(selecting.get("interaction", "")) != "attack_select" or str(selecting.get("selected_skill_id", "")) != skill_id:
		return _strike_or_wait(Loop.cancel_interaction(selecting), id, "", rng, moved) if moved else {}
	# Settlement draws from the loop's damage stream (DamageRandomStream), as the product does.
	var cast := Loop.attack_target(selecting, target_id, null, intent["cast_center"])
	if BattleOutcome.decided(cast):
		return {"loop": cast, "action": action}
	if not bool(cast.get("attacked_this_action", false)):
		return _strike_or_wait(Loop.cancel_interaction(cast), id, "", rng, moved) if moved else {}
	if Loop.loot_waiting(cast):
		return {"loop": cast, "action": action}
	return {"loop": Loop.finish_exhausted_action(cast), "action": action}


## Moves the healer next to the target and uses the item; {} when the plan no longer applies.
static func _heal(loop: Dictionary, id: String, plan: Dictionary, board: Dictionary) -> Dictionary:
	var unit := Loop.unit(loop, id)
	var target := Loop.unit(loop, str(plan["target_id"]))
	if not Loop.Presence.living(target):
		return {}
	var cell: Variant = _adjacent_cell(loop, board, unit, target)
	var drink_cell: Variant = plan.get("heal_cell")
	if drink_cell is Vector2i and id == str(plan["target_id"]) and (drink_cell == unit["coord"] or _reachable(loop, unit).has(drink_cell)):
		cell = drink_cell
	if cell == null:
		return {}
	var next := loop
	var moved := false
	if cell != unit["coord"]:
		if not Loop.command_available(next, "move"):
			return {}
		var moving := Loop.move_unit_to(Loop.choose_command(next, "move"), cell)
		if not bool(moving.get("moved_this_action", false)):
			return {}
		next = moving
		moved = true
	if not Loop.command_available(next, "item"):
		return {}
	var used := Loop.use_item(next, str(plan["item_code"]), str(plan["target_id"]))
	if Loop.same_state(used, next) or int((used.get("last_item_use", {}) as Dictionary).get("sequence", 0)) == int((next.get("last_item_use", {}) as Dictionary).get("sequence", 0)):
		return {}
	return {"loop": used, "action": "move_then_item" if moved else "use_item"}
