extends RefCounted

## Read-only test face of the pure rule modules: queries the suites (and the autoplay brain)
## ask that no product path asks. Each is a static function over plain data, built only on
## the rule modules' public helpers; nothing here holds or writes state. Lives under
## tests/support so game/ carries no player-invisible query surface.

const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const CombatPresentationTiming = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")


## An ordinary strike's forecast: damage, hit rate and whether it would kill (the packet formula).
static func preview_attack(attacker: Dictionary, defender: Dictionary, rng: Variant = null) -> Dictionary:
	var atk := CoreCombatRules.combat_profile_from_unit(attacker)
	var dfn := CoreCombatRules.combat_profile_from_unit(defender)
	var hit := CoreCombatRules.hit_chance(atk, dfn)
	var dmg := CoreCombatRules.preview_damage(atk, dfn, rng)
	return {
		"schema": "hsl_core_attack_preview.v1",
		"damage": int(dmg.get("damage", 1)),
		"hit_rate": int(hit.get("hit_chance", 10)),
		"would_kill": int(dmg.get("damage", 1)) >= int(defender.get("hp", 0)),
		"hit": hit,
		"damage_detail": dmg,
		"packet": combat_packet_summary(),
		"formula_source": "core_logic_packet",
	}


## The combat rules' evidence surface: packet, source functions and what stays unresolved.
static func combat_packet_summary() -> Dictionary:
	return {
		"schema": "hsl_core_combat_rules_surface.v1",
		"packet_path": CoreCombatRules.PACKET_PATH,
		"evidence_doc": CoreCombatRules.EVIDENCE_DOC,
		"hit_function": CoreCombatRules.HIT_ADDR,
		"damage_function": CoreCombatRules.DAMAGE_ADDR,
		"equip_function": CoreCombatRules.EQUIP_ADDR,
		"resolve_function": CoreCombatRules.RESOLVE_ADDR,
		"stat_refresh_function": CoreCombatRules.REFRESH_ADDR,
		"resolved_fields": {
			"str": "0x4c",
			"dex": "0x50",
			"mind": "0x54",
			"con": "0x58",
		},
		"unresolved_semantics": [
			"Whole native actor/weapon initialization and display clock remain separate from numeric helpers",
			"Full actor initial ST and whole exchange RNG; gain helper is in StaminaRules",
			"BCMD post-select handlers; see CoreTurnQueue for queue/menu surface",
		],
		"related_surfaces": {
			"turn_queue": "res://game/sim/CoreTurnQueue.gd",
		},
	}


## The turn queue's evidence surface.
static func turn_queue_packet_summary() -> Dictionary:
	return {
		"schema": "hsl_core_turn_queue_surface.v1",
		"packet_path": CoreTurnQueue.PACKET_PATH,
		"evidence_doc": CoreTurnQueue.EVIDENCE_DOC,
		"rebuild_function": CoreTurnQueue.REBUILD_ADDR,
		"current_object_function": CoreTurnQueue.CURRENT_ADDR,
		"advance_function": CoreTurnQueue.ADVANCE_ADDR,
		"status_tickdown_function": CoreTurnQueue.STATUS_TICK_ADDR,
		"menu_builder_function": CoreTurnQueue.MENU_BUILDER_ADDR,
		"sort_key": "live_speed",
		"sort_order": "descending",
		"unresolved_semantics": [
			"NPC registration follows roster (creation) order; native free-slot reuse after the 200-slot wrap is not modelled",
			"BCMD post-select handler mapping",
		],
	}


static func can_player_control_actor(unit: Dictionary, role_model: Dictionary = {}) -> bool:
	return ActorRoleRules.battle_actor_role(unit, role_model) == "player_controlled" and int(unit.get("hp", 0)) > 0


static func can_player_attack_actor(attacker: Dictionary, target: Dictionary, role_model: Dictionary = {}) -> bool:
	return can_player_control_actor(attacker, role_model) and int(target.get("hp", 0)) > 0 and ActorRoleRules.hostile(attacker, target, role_model)


static func annotate_actor_role(unit: Dictionary, role_model: Dictionary = {}) -> Dictionary:
	var next_unit := unit.duplicate(true)
	var role := ActorRoleRules.battle_actor_role(next_unit, role_model)
	next_unit["battle_actor_role"] = role
	return next_unit


static func battle_actor_role_summary(units: Array, role_model: Dictionary = {}) -> Dictionary:
	var counts := {}
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		var unit_data: Dictionary = unit
		var role := ActorRoleRules.battle_actor_role(unit_data, role_model)
		counts[role] = int(counts.get(role, 0)) + 1
	return {
		"schema": "hsl_battle_actor_roles.v1",
		"counts": counts,
		"semantics": "Explicit battle actor role boundary for player control, friendly AI, enemy AI, map objects, and battle manager records.",
	}


static func movement_range(unit: Dictionary, units: Array, tiles: Dictionary, map_size: Vector2i) -> Array:
	return TacticalGridRules.movement_reachability_envelope(unit, units, tiles, map_size).get("reachable_coords", [])


static func attack_range(origin: Vector2i, min_range: int, max_range: int, map_size: Vector2i) -> Array:
	var lower := maxi(min_range, 0)
	var upper := maxi(max_range, lower)
	var coords: Array = []
	for y in range(map_size.y):
		for x in range(map_size.x):
			var coord := Vector2i(x, y)
			var distance := TacticalGridRules.manhattan(origin, coord)
			if distance >= lower and distance <= upper:
				coords.append(coord)
	return coords


static func condition_tokens(status: Dictionary) -> Array:
	var tokens: Array = []
	for condition_value in status.get("conditions", []):
		var condition: Dictionary = condition_value
		var args: Array = condition["args"]
		match str(condition["name"]):
			"actCheckPlayer", "actCheckEnemy":
				for index in range(1, args.size()):
					tokens.append(WinfailConditions.arg(args, index))
			"actCheckPlayerArrivePos", "actCheckPlayerHPLow", "actCheckEnemyNumber":
				if args.size() >= 1:
					tokens.append(WinfailConditions.arg(args, 0))
	return tokens


static func native_target_mode(channel: String, mask: int) -> int:
	if mask <= 0 or channel not in ["magic", "special"]:
		return -1
	var support := SkillTargetRules.MAGIC_SUPPORT_MASK if channel == "magic" else SkillTargetRules.SPECIAL_SUPPORT_MASK
	return 3 if (mask & support) != 0 else 2


## The cut-in phase name `elapsed` seconds into a CombatPresentationTiming schedule.
static func phase_at(schedule: Dictionary, elapsed: float) -> String:
	for phase in ["opening", "release", "target", "impact", "recovery", "darkened", "complete"]:
		if elapsed < float(schedule[phase]):
			return {"opening": "opening", "release": "windup", "target": "release", "impact": "target_pause", "recovery": "hurt", "darkened": "recovery", "complete": "closing"}[phase]
	return "complete"


## The section title card's state after `tick` ticks when a key／click reaches the hold on
## hold tick `skip_hold_tick` (0 = never; the hold then runs its 320 ticks).
static func section_title_state_at(tick: int, skip_hold_tick: int = 0) -> Dictionary:
	var state := OpeningCinematics.section_title_new_state()
	var hold_ticks := 0
	while int(state["tick"]) < tick and int(state["sub"]) != OpeningCinematics.TITLE_SUB_DONE:
		var holding := int(state["sub"]) == 4
		if holding:
			hold_ticks += 1
		OpeningCinematics.section_title_step(state, holding and hold_ticks == skip_hold_tick)
	return state
