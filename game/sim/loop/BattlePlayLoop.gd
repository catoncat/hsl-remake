extends RefCounted
## Mechanics-playable battle loop: the single owner of the mutable battle state (one loop
## dictionary — units, queue, interaction, receipts). This file is the contract facade and
## the player's command flow: selection／menus, movement, attack targeting, the action
## budget (`settle_action`), the one queue-advance seam (`advance_current_actor`) and the
## unit lookups every module shares (`unit_ref`, `set_unit_*`, `are_enemies`…). The other
## responsibilities are static modules operating on the same dictionary (none owns state),
## forwarded from here so the 91 callers see one surface: BattleLoopInit (create),
## BattleLoopRewards (settlement／loot／experience), BattleLoopScript (outcome and script
## transactions), BattleLoopAI (AI turns), BattleLoopCombat (exchange／skill commit),
## BattleLoopInventory (use／give／equip). Original fidelity remains required; the opening
## timeline is owned by BattleSceneRuntime, this loop owns post-control play.
## Internal interface for the BattleLoop* modules (public names, not for scene code; scene
## and panels read through `unit` (a copy) and the command functions):
##   unit_ref (the live unit dictionary), set_unit_coord, set_unit_hp, set_unit_defeated,
##   are_enemies, is_current_actor, mark_known, queue_actors, advance_current_actor,
##   return_to_player, finish_ai_or_continue, settle_action, clear_extra_action,
##   player_action_valid, skill_input_error, magic_position_error, extra_action_input_error,
##   traversal_context, menu_for_unit, product_command_menu, movement_envelope,
##   resolve_outcome, reward_input_error, resource_input_error.
## Underscore functions are used in this file only.
## provenance:
##   rules: static-derived content/generated/hsl/static/hsl01/core_logic.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##   rules: runtime-measured docs/evidence_packets/static_reverse/original_identity_bar.md#runtime-measured
##     (known byte indexed by PLAYERS template row obj+0xa2 — unit_known reads any known unit of the actor_id)
##   rules: resource-derived content/generated/hsl/skills/initial_book.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_round_display.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_death_disposal.md
##   rules: runtime-reference docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##     (特殊技 always opens the skill page first, even with one skill and an empty gauge; then the cell)
##   rules: remake-invented
##     (one-owner transaction ordering, action-budget hand-off and menu surface — docs/architecture/BATTLE_SYSTEMS.md)

const WeaponEffects = preload("res://game/sim/WeaponEffectRules.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const Treasure = preload("res://game/sim/TreasureRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const ActionBudgetRules = preload("res://game/sim/ActionBudgetRules.gd")
const ActionEntryRules = preload("res://game/sim/ActionEntryRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const MobilityRules = preload("res://game/sim/MobilityRules.gd")
const TraversalRules = preload("res://game/sim/ActorTraversalRules.gd")
const ExtraActionRules = preload("res://game/sim/ExtraActionRules.gd")
const PositionCapabilities = preload("res://game/sim/PositionCapabilityRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const TurnEndRules = preload("res://game/sim/TurnEndRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")
const PoisonGasRules = preload("res://game/sim/PoisonGasRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")

const ROLE_PLAYER := "player_controlled"
const ROLE_ENEMY := "enemy_ai"
const ROLE_FRIENDLY := "friendly_ai"
const IMPLEMENTED_COMMANDS := ["move", "attack", "item", "wait", "status", "special", "magic"]

## Read-only configuration versus mutable state: every `_load_*` stage of create() that
## stores a scenario-side input registers its key in BattleLoopConfig.CONFIG_SHARED; after
## create() those values are never written in place, so `copy` shares them by reference
## between successive loops (BattleCheckpoint saves the state keys only; tests re-hash the
## shared blocks at the end of every rule suite). Contract: docs/architecture/BATTLE_CONFIG_STATE.md.
const LoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const CONFIG_KEYS := LoopConfig.CONFIG_KEYS
const CONFIG_SHARED := LoopConfig.CONFIG_SHARED


## The one way to copy a whole loop (state deep-copied, configuration shared).
static func copy(loop: Dictionary) -> Dictionary:
	return LoopConfig.copy(loop)


## True when the two loops agree on every state key (the configuration is shared).
static func same_state(left: Dictionary, right: Dictionary) -> bool:
	return LoopConfig.same_state(left, right)


## Static modules operating on the same loop dictionary (none owns state): initialization,
## settlement (rewards／loot／experience／growth allocation), script progression (outcome
## resolution, script actors／waits／departures／reinforcement pressure), AI turn driving,
## the combat commit seam player and AI share (exchange／strike／skill receipts), inventory
## and equipment transactions (use／drop／give／equip, storage projection).
const BattleLoopInit = preload("res://game/sim/loop/BattleLoopInit.gd")
const BattleLoopRewards = preload("res://game/sim/loop/BattleLoopRewards.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const AI = preload("res://game/sim/loop/BattleLoopAI.gd")
const Combat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleLoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")

## Rule modules re-exported for callers that reach them through this facade (`Loop.X`);
## the facade's own code no longer calls them — the owning module above does.
const BattleScenario = BattleLoopInit.BattleScenario
const WrdTerrainTiles = BattleLoopInit.WrdTerrainTiles
const InitialRosterGrowth = BattleLoopInit.InitialRosterGrowthRules
const RewardRules = BattleLoopRewards.BattleRewardRules
const ScriptWait = BattleLoopScript.ScriptWait
const ReinforcementGrowth = BattleLoopScript.ReinforcementGrowth
const ScriptActors = BattleLoopScript.ScriptActorCreationRules
const ItemUseRules = AI.ItemUseRules
const SkillResourceRules = AI.SkillResourceRules
const AISkillPlanning = AI.AISkillPlanning
const AINavigationRules = AI.AINavigationRules
const CombatSequence = Combat.CombatSequence
const InventoryRules = BattleLoopInventory.InventoryRules
const EquipmentRules = BattleLoopInventory.EquipmentRules
const CampaignCarryRules = BattleLoopInventory.CampaignCarryRules
const ItemResolutionRules = BattleLoopInventory.ItemResolutionRules


## Build the loop from a scenario (BattleLoopInit: `_initial_loop` + the `_load_*` stages).
static func create(units: Array = [], terrain_path: String = "", scenario: Dictionary = {}, reward_seed: int = 1, global_state: Array = []) -> Dictionary:
	return BattleLoopInit.create(units, terrain_path, scenario, reward_seed, global_state)


static func initialize_roster_growth(loop: Dictionary) -> Dictionary:
	return BattleLoopInit.initialize_roster_growth(loop)


static func apply_campaign_carry(loop: Dictionary, carry: Dictionary) -> Dictionary:
	return BattleLoopInit.apply_campaign_carry(loop, carry)


static func summary(loop: Dictionary) -> Dictionary:
	var cur: Dictionary = CoreTurnQueue.current(loop.get("turn_queue", {}))
	return {
		"schema": "hsl_first_scene_play_loop_summary.v1",
		"current_actor_id": str(cur.get("id", "")),
		"round": int((loop.get("turn_queue", {}) as Dictionary).get("round", 0)),
		"interaction": str(loop.get("interaction", "")),
		"selected_unit_id": str(loop.get("selected_unit_id", "")),
		"pending_move": bool(loop.get("pending_move", false)),
		"moved_this_action": bool(loop.get("moved_this_action", false)),
		"attacked_this_action": bool(loop.get("attacked_this_action", false)),
		"battle_outcome": BattleOutcome.of(loop),
		"turn": int(loop.get("turn", 1)),
		"objective_phase": str(loop.get("objective_phase", "hold")),
		"event_log": loop.get("event_log", []).duplicate(true),
		"escape_zone": loop.get("escape_zone", []).duplicate(),
		"terrain_ok": bool(loop.get("terrain_ok", false)),
		"terrain_blocking_count": int(loop.get("terrain_blocking_count", 0)),
		"alive_unit_count": _alive_units(loop).size(),
		"command_ids": _command_ids(loop),
		"formula_source": str(loop.get("formula_source", "")),
		"last_ai_action_count": (loop.get("last_ai_actions", []) as Array).size(),
		"last_command_reject": (loop.get("last_command_reject", {}) as Dictionary).duplicate(true),
	}


static func begin_battle(loop: Dictionary) -> Dictionary:
	var next := copy(loop)
	if not bool(next.get("scenario_ok", false)) or BattleOutcome.decided(next):
		return next
	var current: Dictionary = CoreTurnQueue.current(next["turn_queue"])
	var actor: Dictionary = unit_ref(next, str(current.get("id", "")))
	if actor.is_empty():
		return next
	if bool(actor.get("player_commandable", false)):
		return return_to_player(next, str(actor["id"]))
	next["interaction"] = "ai_resolving"
	next["selected_unit_id"] = ""
	return next


static func select_player_unit(loop: Dictionary, unit_id: String) -> Dictionary:
	if loot_waiting(loop): return copy(loop)
	if not loop.get("give_session", {}).is_empty():
		return copy(loop)
	if BattleOutcome.decided(loop) or not bool(loop.get("scenario_ok", false)):
		return copy(loop)
	var next := copy(loop)
	var unit: Dictionary = unit_ref(next, unit_id)
	if unit.is_empty() or not bool(unit.get("player_commandable", false)):
		return next
	if not is_current_actor(next, unit_id):
		return next
	next["selected_unit_id"] = unit_id
	next["interaction"] = "action_menu"
	next["command_menu"] = menu_for_unit(next, unit_id)
	return next


static func choose_command(loop: Dictionary, command: String) -> Dictionary:
	var next := copy(loop)
	if not player_action_valid(loop, "action_menu", true):
		return next
	if command not in IMPLEMENTED_COMMANDS:
		next["last_command_reject"] = {
			"command": command,
			"reason": "not_implemented",
		}
		return next
	if not command_available(loop, command):
		return next
	next["last_command_reject"] = {}
	match command:
		"move":
			return settle_action(next, "select_move")
		"special":
			# 特殊技 always opens the skill page, also for a single skill and when 氣力 pays
			# none of it (recording 46.5–54.75 s): the page describes the rows and the player
			# leaves it by cancelling; choose_special starts the target selection.
			next = settle_action(next, "select_special")
			next["selected_skill_id"] = ""
			next["interaction"] = "special_select"
			return next
		"attack", "magic":
			return settle_action(next, "select_" + command)
		"wait":
			return settle_action(next, "wait")
		"status", "item":
			return settle_action(next, command)
	return next


static func command_available(loop: Dictionary, command: String) -> bool:
	if command not in IMPLEMENTED_COMMANDS or not player_action_valid(loop, "action_menu", true):
		return false
	if not ActionBudgetRules.command_available(command, bool(loop["moved_this_action"]), bool(loop["attacked_this_action"])):
		return false
	if command == "magic":
		return magic_position_error(loop, unit_ref(loop, str(loop["selected_unit_id"]))) == "" and not magic_options(loop, str(loop["selected_unit_id"])).is_empty()
	if command == "attack":
		var actor := unit_ref(loop, str(loop["selected_unit_id"]))
		if bool(actor.get("no_attack", false)): return false
		var pattern := weapon_pattern(loop, actor)
		return pattern.get("ok", false) and not pattern.get("offsets", []).is_empty()
	return command != "special" or special_page_available(loop, str(loop["selected_unit_id"]))


static func skill_fields(loop: Dictionary, skill_id: String) -> Dictionary:
	return loop["skill_book"]["skills"].get(skill_id, {}).get("fields", {})


static func magic_options(loop: Dictionary, unit_id: String) -> Array:
	var actor := unit_ref(loop, unit_id)
	var result: Array = []
	for id in loop["skill_book"]["skills"]:
		var entry: Dictionary = loop["skill_book"]["skills"][id]
		if entry["channel"] != "magic" or SkillResolutionRules.ownership_error(actor, id, loop["skill_book"]) != "": continue
		var quote := SkillResolutionRules.available(actor, id, skill_fields(loop, id), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])
		var position_error := magic_position_error(loop, actor)
		if position_error != "": quote = {"ok": false, "reason": position_error}
		result.append({"id": id, "name": entry["name"], "quote": quote, "fields": skill_fields(loop, id)})
	return result


static func choose_magic(loop: Dictionary, skill_id: String) -> Dictionary:
	if not player_action_valid(loop, "magic_select"): return copy(loop)
	var actor := unit_ref(loop, str(loop["selected_unit_id"]))
	if magic_position_error(loop, actor) != "": return copy(loop)
	var entry: Dictionary = loop["skill_book"]["skills"].get(skill_id, {})
	if entry.get("channel") != "magic": return copy(loop)
	var quote := SkillResolutionRules.available(actor, skill_id, skill_fields(loop, skill_id), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])
	if not quote["ok"]: return copy(loop)
	var next := copy(loop)
	next["selected_attack"] = "magic"
	next["selected_skill_id"] = skill_id
	next["interaction"] = "attack_select"
	return next


static func special_options(loop: Dictionary, unit_id: String) -> Array:
	var actor := unit_ref(loop, unit_id)
	var options: Array = []
	for id in loop["skill_book"]["skills"]:
		var entry: Dictionary = loop["skill_book"]["skills"][id]
		if entry["channel"] != "special" or SkillResolutionRules.ownership_error(actor, id, loop["skill_book"]) != "": continue
		options.append({"id": id, "name": entry["name"], "fields": skill_fields(loop, id),
			"quote": SkillResolutionRules.available(actor, id, skill_fields(loop, id), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])})
	return options


static func choose_special(loop: Dictionary, skill_id: String) -> Dictionary:
	if not player_action_valid(loop, "special_select"): return copy(loop)
	for option in special_options(loop, str(loop["selected_unit_id"])):
		if option["id"] != skill_id or not option["quote"]["ok"]: continue
		var next := copy(loop)
		next.merge({"selected_attack": "special", "selected_skill_id": skill_id, "interaction": "attack_select"}, true)
		return next
	return copy(loop)


static func player_action_valid(loop: Dictionary, phase: String, allow_completed: bool = false) -> bool:
	if loot_waiting(loop): return false
	if not bool(loop.get("scenario_ok", false)) or BattleOutcome.decided(loop) or loop.get("interaction") != phase:
		return false
	if phase != "give_session" and not loop.get("give_session", {}).is_empty():
		return false
	if not allow_completed and bool(loop.get("attacked_this_action", false)):
		return false
	var id := str(loop.get("selected_unit_id", ""))
	var actor := unit_ref(loop, id)
	if extra_action_input_error(loop) != "" or not ExtraActionRules.equipment(actor, loop["equipment_items"])["ok"]: return false
	if resource_input_error(loop, actor) != "": return false
	return id != "" and is_current_actor(loop, id) and bool(actor.get("player_commandable", false)) and int(actor.get("hp", 0)) > 0 and not bool(actor.get("defeated", false)) and StatusEffectRules.input_error(actor) == "" and not StatusEffectRules.paralyzed(actor)


static func cancel_interaction(loop: Dictionary) -> Dictionary:
	if not loop.get("give_session", {}).is_empty():
		return copy(loop)
	if BattleOutcome.decided(loop) or not bool(loop.get("scenario_ok", false)):
		return copy(loop)
	var next := copy(loop)
	var state := str(next.get("interaction", ""))
	if not player_action_valid(loop, state):
		return next
	if state in ["move_select", "attack_select", "magic_select", "special_select"]:
		return settle_action(next, "cancel_selection")
	elif bool(next.get("pending_move", false)):
		return cancel_pending_move(next)
	return next


static func movement_cells(loop: Dictionary, unit_id: String = "") -> Array:
	return movement_envelope(loop, unit_id).get("reachable_coords", [])


static func movement_path(loop: Dictionary, unit_id: String, target: Vector2i) -> Array:
	return movement_envelope(loop, unit_id).get("reachable_by_coord", {}).get(target, {}).get("path", [])


## Memo of `TraversalRules.tile_tables(TerrainEdits.tiles(loop), loop["map_size"])`: the map
## is a CONFIG_SHARED block, never written in place after create(), and a mid-battle edit
## yields one memoised edited copy (TerrainEditRules), so the per-cell tables are rebuilt
## only when that reference or the map size differs (another battle, a terrain edit, a test
## that took its own copy). Lives outside the loop dictionary (never copied／saved／compared).
static var _tile_tables := {"tiles": null, "map_size": Vector2i.ZERO, "tables": {}}


## `TraversalRules.prepare(unit, units, TerrainEdits.tiles(loop))` over the memoised tile tables.
static func traversal_context(loop: Dictionary, unit: Dictionary, units: Array) -> Dictionary:
	var tiles: Dictionary = TerrainEdits.tiles(loop)
	var map_size: Vector2i = loop.get("map_size", Vector2i(24, 24))
	if not is_same(_tile_tables["tiles"], tiles) or _tile_tables["map_size"] != map_size:
		_tile_tables = {"tiles": tiles, "map_size": map_size, "tables": TraversalRules.tile_tables(tiles, map_size)}
	return TraversalRules.prepare(unit, units, tiles, _tile_tables["tables"])


## `traversal`: the unit's accepted TraversalRules context when the caller holds one.
static func movement_envelope(loop: Dictionary, unit_id: String, traversal: Dictionary = {}) -> Dictionary:
	var id := unit_id if unit_id != "" else str(loop.get("selected_unit_id", ""))
	var unit: Dictionary = unit_ref(loop, id)
	if not Presence.living(unit):
		return {}
	var units: Array = _alive_units(loop)
	for actor in units:
		var error := TraversalRules.actor_error(actor, loop["skill_book"])
		if error != "": return {"ok": false, "reason": error, "reachable_coords": [], "reachable_by_coord": {}, "transit_by_coord": {}, "blocked_coords": {}}
	var envelope: Dictionary = TacticalGridRules.movement_reachability_envelope(
		unit,
		units,
		TerrainEdits.tiles(loop),
		loop.get("map_size", Vector2i(24, 24)),
		int(unit["move_point"]),
		traversal if not traversal.is_empty() else traversal_context(loop, unit, units)
	)
	return envelope


static func attack_cells(loop: Dictionary, unit_id: String = "") -> Array:
	var id := unit_id if unit_id != "" else str(loop.get("selected_unit_id", ""))
	var unit: Dictionary = unit_ref(loop, id)
	if not Presence.living(unit):
		return []
	var origin: Vector2i = unit.get("coord", Vector2i.ZERO)
	if loop.get("selected_attack") == "magic" and loop["interaction"] == "attack_select" and id == loop["selected_unit_id"]:
		return SkillTargetRules.cells(origin, skill_fields(loop, str(loop.get("selected_skill_id", ""))), loop["skill_target_data"], loop["map_size"], skill_terrain(loop))
	if str(loop.get("selected_attack", "attack")) == "special" and str(loop["interaction"]) == "attack_select" and id == str(loop["selected_unit_id"]):
		return SkillTargetRules.cells(origin, skill_fields(loop, str(loop["selected_skill_id"])), loop["skill_target_data"], loop["map_size"], skill_terrain(loop))
	var pattern := weapon_pattern(loop, unit)
	if not pattern["ok"]: return []
	return weapon_cells(loop, unit, pattern)


## The cells a unit's weapon covers from its own cell: the original 0x40f8b0 flood over the
## map words (RangePropagationRules) — 0x4000 walls stop it, an occupant of the builder's
## side is left out. Mode 2 for a player-controlled unit (0x444156 pushes 2), otherwise
## the unit's 0x40bab0 side mode (counters, AI); flag 1. The unit's own cell is never kept.
static func weapon_cells(loop: Dictionary, unit: Dictionary, pattern: Dictionary) -> Array:
	var origin: Vector2i = unit["coord"]
	var rows: Variant = loop["attack_patterns"].get(str(pattern.get("name", "")), {}).get("data")
	if pattern["offsets"].is_empty() or not rows is Array:
		return TacticalGridRules.attack_pattern_cells(origin, pattern["offsets"], loop["map_size"])
	var mode := 2 if str(unit.get("battle_actor_role", "")) == "player_controlled" else RangePropagationRules.offensive_mode(unit)
	return RangePropagationRules.cells(RangePropagationRules.weapon_coverage(rows, origin, RangePropagationRules.loop_words(loop), loop["map_size"], mode, true), origin)


## The player's skill terrain (the command path 0x444eb7／0x444f08／0x4450e0): the cast range
## follows the original 0x40f8b0 mode -1 flood and the effect area the 0x4100e0 flood or line
## at mode 2 offensive／3 support — walls stop both, the area leaves out the mode's excluded
## side. Selection, the hover footprint (BattleLoopCombat.skill_cast_footprint), the hover
## target line and the settled cast (BattleLoopCombat.skill_context) all read this one set.
## The caster is `caster`, else the selected unit. The area half needs a P-side caster: the
## command path passes the constants 2／3, which only exist for the player's side; any other
## caster keeps the flat area (the cast range, mode -1, excludes no side and always applies).
static func skill_terrain(loop: Dictionary, caster: Dictionary = {}) -> Dictionary:
	var unit := caster if not caster.is_empty() else unit_ref(loop, str(loop.get("selected_unit_id", "")))
	return RangePropagationRules.player_skill_terrain(loop, not unit.is_empty() and RangePropagationRules.side_word(unit) & RangePropagationRules.P != 0)


## `skill_terrain` while the player's command cast is in progress — the selected unit's
## magic／special in attack_select — else {}. BattleLoopCombat.skill_context adds it to the
## settled cast so a player cast settles over the propagated area; an AI cast (ai_resolving)
## keeps the flat projection its planner reads until the AI side is wired.
static func player_cast_terrain(loop: Dictionary) -> Dictionary:
	if str(loop.get("interaction", "")) != "attack_select" or loop.get("selected_attack") not in ["magic", "special"] or unit_ref(loop, str(loop.get("selected_unit_id", ""))).is_empty(): return {}
	return skill_terrain(loop)


static func weapon_pattern(loop: Dictionary, actor: Dictionary) -> Dictionary:
	return PositionCapabilities.attack_pattern(actor, loop["equipment_items"], loop["attack_patterns"], loop["weapon_ranges"])


static func magic_position_error(loop: Dictionary, actor: Dictionary) -> String:
	var moved: bool = actor.get("id") == loop.get("selected_unit_id") and bool(loop.get("moved_this_action", false))
	return PositionCapabilities.cast_error(actor, loop["skill_book"], loop["equipment_items"], "magic", moved)


static func strike_range_cells(loop: Dictionary, strike: Dictionary) -> Array:
	## Read-only geometry for a settled exchange, independent of the NEXT actor's menu.
	var attacker := unit_ref(loop, str(strike["attacker_id"]))
	var origin: Vector2i = attacker["coord"]
	if strike.has("magic_key"):
		return SkillTargetRules.cells(origin, skill_fields(loop, str(strike.get("skill_id", ""))), loop["skill_target_data"], loop["map_size"], skill_terrain(loop))
	elif strike.has("skill_name"):
		var fields := skill_fields(loop, str(strike["skill_id"]))
		# A player's cast settled over the propagated area, an AI cast over the flat one.
		var area_terrain := skill_terrain(loop, attacker) if bool(attacker.get("player_commandable", false)) else {}
		# A settled line special (皇龍閃 etc.) cues its actual line from the chosen cell.
		if strike.get("cast_center") is Vector2i and SkillTargetRules.is_line(loop["skill_target_data"]["ranges"].get(fields.get("effect_range"))):
			return SkillTargetRules.effect_cells(strike["cast_center"], fields, loop["skill_target_data"], loop["map_size"], origin, area_terrain)
		return SkillTargetRules.effect_cells(origin, fields, loop["skill_target_data"], loop["map_size"], origin, area_terrain) if SkillTargetRules.self_centered(fields) else SkillTargetRules.cells(origin, fields, loop["skill_target_data"], loop["map_size"], skill_terrain(loop))
	var pattern := weapon_pattern(loop, attacker)
	if not pattern["ok"]: return []
	return weapon_cells(loop, attacker, pattern)


static func move_unit_to(loop: Dictionary, target: Vector2i) -> Dictionary:
	if not player_action_valid(loop, "move_select"):
		return copy(loop)
	var next := copy(loop)
	var unit_id := str(next.get("selected_unit_id", ""))
	if unit_id == "" or str(next.get("interaction", "")) != "move_select":
		return next
	if bool(next.get("moved_this_action", false)):
		return next
	var cells: Array = movement_cells(next, unit_id)
	if not cells.has(target):
		return next
	var unit: Dictionary = unit_ref(next, unit_id)
	next["pending_move_from"] = unit.get("coord", Vector2i.ZERO)
	set_unit_coord(next, unit_id, target)
	return settle_action(next, "move")


static func cancel_pending_move(loop: Dictionary) -> Dictionary:
	if not player_action_valid(loop, "action_menu"):
		return copy(loop)
	var next := copy(loop)
	var unit_id := str(next.get("selected_unit_id", ""))
	if unit_id == "" or not bool(next.get("pending_move", false)):
		return next
	var actor := unit_ref(next, unit_id)
	var destination: Vector2i = next["pending_move_from"]
	var clearance := TraversalRules.prepare(actor, next["units"], TerrainEdits.tiles(next))
	if not clearance["ok"] or TraversalRules.stop_error(destination, clearance) != "": return copy(loop)
	if Footprint.radius(actor) == 1 and TraversalRules.transition_error(destination, destination, clearance, TerrainEdits.tiles(next)) != "": return copy(loop)
	set_unit_coord(next, unit_id, destination)
	return settle_action(next, "cancel_move")


static func unit_id_at_coord(loop: Dictionary, coord: Vector2i) -> String:
	return str(Footprint.unit_at(loop["units"], coord).get("id", ""))


static func attack_target(loop: Dictionary, target_unit_id: String, rng: Variant = null, center_coord: Variant = null) -> Dictionary:
	if loot_waiting(loop) or BattleLoopRewards.reward_input_error(loop) != "": return copy(loop)
	if BattleOutcome.decided(loop) or not bool(loop.get("scenario_ok", false)):
		return copy(loop)
	var next := copy(loop)
	var attacker_id := str(next.get("selected_unit_id", ""))
	if attacker_id == "" or str(next.get("interaction", "")) != "attack_select":
		next["last_attack_reject"] = {"reason": "not_in_attack_select"}
		return next
	if bool(next.get("attacked_this_action", false)):
		next["last_attack_reject"] = {"reason": "already_attacked"}
		return next
	var attacker: Dictionary = unit_ref(next, attacker_id)
	var defender: Dictionary = unit_ref(next, target_unit_id)
	if not attacker.is_empty() and StatusEffectRules.input_error(attacker) != "":
		return copy(loop)
	if attacker.is_empty() or defender.is_empty():
		next["last_attack_reject"] = {"reason": "missing_unit", "target_unit_id": target_unit_id}
		return next
	if not is_current_actor(next, attacker_id) or not bool(attacker.get("player_commandable", false)) or bool(attacker.get("no_attack", false)) or bool(attacker.get("defeated", false)) or int(attacker.get("hp", 0)) <= 0 or StatusEffectRules.paralyzed(attacker):
		next["last_attack_reject"] = {"reason": "invalid_current_attacker"}
		return next
	if not Presence.living(defender):
		next["last_attack_reject"] = {"reason": "target_defeated"}
		return next
	# Skill casts (magic or special) settle their side through SkillTargetRules.side_matches;
	# support specials (萬息集氣法, 千羽風靈壁...) legitimately target allies or the caster.
	if next.get("selected_attack") not in ["magic", "special"] and not ActorRoleRules.player_range_selectable(attacker, defender, false):
		next["last_attack_reject"] = {"reason": "not_enemy", "target_unit_id": target_unit_id}
		return next
	var special := str(next.get("selected_attack", "attack")) == "special"
	var magic: bool = next.get("selected_attack") == "magic"
	var skill_id := str(next.get("selected_skill_id", "")) if magic or special else ""
	var self_centered := special and SkillTargetRules.self_centered(skill_fields(next, skill_id))
	if self_centered and center_coord == null: center_coord = attacker["coord"]
	if magic:
		var position_error := magic_position_error(next, attacker)
		if position_error != "":
			next["last_attack_reject"] = {"reason": position_error}
			return next
		var ready := SkillResolutionRules.prepare_cast(attacker, defender, next["units"], skill_id, skill_fields(next, skill_id), next["skill_book"], next["skill_target_data"], next["equipment_items"], attacker["coord"], next["map_size"], center_coord, {"range_terrain": skill_terrain(next)})
		if not ready["ok"]:
			next["last_attack_reject"] = {"reason": ready["reason"]}
			return next
	if special:
		var ready := SkillResolutionRules.prepare_cast(attacker, defender, next["units"], skill_id, skill_fields(next, skill_id), next["skill_book"], next["skill_target_data"], next["equipment_items"], attacker["coord"], next["map_size"], center_coord, Combat.skill_context(next))
		if not ready["ok"]:
			next["last_attack_reject"] = {"reason": ready["reason"]}
			return next
	var cells: Array = attack_cells(next, attacker_id)
	var def_coord: Variant = center_coord if center_coord is Vector2i else Footprint.contact(defender, cells)
	# Shared preparation already validates each skill's center/footprint contract.
	# A non-self area special can use an empty center just like an area spell;
	# only an ordinary strike additionally requires a cell on the target's body.
	if not def_coord is Vector2i or not cells.has(def_coord) or (not magic and not special and not Footprint.contains(defender, def_coord)):
		next["last_attack_reject"] = {
			"reason": "out_of_range",
			"target_unit_id": target_unit_id,
			"target_coord": def_coord,
			"attacker_coord": attacker.get("coord", Vector2i.ZERO),
		}
		return next

	mark_known(next, target_unit_id)
	var strike := Combat.resolve_skill(next, attacker_id, target_unit_id, skill_id, skill_fields(next, skill_id), attacker["coord"], rng, def_coord) if special or magic else Combat.resolve_exchange(next, attacker_id, target_unit_id, rng)
	if strike.is_empty():
		return copy(loop)
	strike["cast_center"] = def_coord
	next["last_attack_reject"] = {}
	next["last_attack"] = strike
	# The remake's 0x4c1ce8 attacker global: the attack cases of this action's completion
	# scan read it (advance_current_actor); there is no scan after the strike itself.
	next["action_attacker_id"] = attacker_id
	next = settle_action(next, "magic" if magic else ("special" if special else "attack"))
	return BattleLoopScript.resolve_outcome(next)


static func attack_coord(loop: Dictionary, coord: Vector2i, rng: Variant = null) -> Dictionary:
	var skill: bool = loop.get("selected_attack") in ["magic", "special"]
	var target_id := magic_target_id_at_coord(loop, coord) if skill else unit_id_at_coord(loop, coord)
	if target_id == "":
		var next := copy(loop)
		next["last_attack_reject"] = {"reason": "no_unit_at_coord", "coord": coord}
		return next
	return attack_target(loop, target_id, rng, coord)


static func magic_target_id_at_coord(loop: Dictionary, coord: Vector2i) -> String:
	var actor := unit_ref(loop, str(loop.get("selected_unit_id", "")))
	var id := str(loop.get("selected_skill_id", ""))
	if actor.is_empty() or loop.get("selected_attack") not in ["magic", "special"] or not loop["skill_book"]["skills"].has(id): return ""
	var fields := skill_fields(loop, id)
	var terrain := skill_terrain(loop)
	if not SkillTargetRules.cells(actor["coord"], fields, loop["skill_target_data"], loop["map_size"], terrain).has(coord): return ""
	var footprint := SkillTargetRules.effect_cells(coord, fields, loop["skill_target_data"], loop["map_size"], actor["coord"], terrain)
	var fallback := ""
	for target in loop["units"]:
		if not Presence.living(target) or not Footprint.overlaps(target, footprint) or not SkillTargetRules.side_matches(actor, target, fields, loop["skill_target_data"]): continue
		if Footprint.contains(target,coord): return str(target["id"])
		if fallback == "": fallback = str(target["id"])
	return fallback


## test hook
static func commit_wait(loop: Dictionary, rng: Variant = null) -> Dictionary:
	## Instant resolve path (tests / headless). Runtime should prefer begin_wait_resolution + step_ai_turn.
	var next := begin_wait_resolution(loop)
	if str(next.get("interaction", "")) != "ai_resolving":
		return next
	while str(next.get("interaction", "")) == "ai_resolving" and not loot_waiting(next):
		next = step_ai_turn(next, rng)
	return next


static func action_exhausted(loop: Dictionary) -> bool:
	if loot_waiting(loop): return false
	# Ordinary attack and special completion both reach the native common finish,
	# even without prior movement and even on a miss. Presentation still waits.
	var operation := "special" if loop.get("last_attack", {}).has("skill_name") else "attack"
	var id := str(loop.get("selected_unit_id", ""))
	return bool(loop.get("scenario_ok", false)) and id != "" and is_current_actor(loop, id) and loop.get("give_session", {}).is_empty() and str(loop.get("interaction", "")) == "action_menu" and not BattleOutcome.decided(loop) and bool(loop.get("attacked_this_action", false)) and ActionBudgetRules.ends_action(operation)


static func finish_exhausted_action(loop: Dictionary) -> Dictionary:
	# Runtime invokes this only after all combat, movement and modal presentation.
	# Calling it again on the settled successor cannot spend that actor's action.
	return settle_action(copy(loop), "offense_presented") if action_exhausted(loop) else copy(loop)


static func begin_wait_resolution(loop: Dictionary) -> Dictionary:
	if loot_waiting(loop): return copy(loop)
	# Explicit headless/driver entry; all successful command outcomes share this
	# one owner-action commit. Runtime never calls this just to start presentation.
	if not loop.get("give_session", {}).is_empty():
		return copy(loop)
	if BattleOutcome.decided(loop) or not bool(loop.get("scenario_ok", false)):
		return copy(loop)
	var next := copy(loop)
	var finishing_id := str(CoreTurnQueue.current(next["turn_queue"]).get("id", ""))
	var unit_id := str(next.get("selected_unit_id", ""))
	if unit_id == "" or not is_current_actor(next, unit_id) or next.get("interaction") != "action_menu":
		return next
	if StatusEffectRules.input_error(unit_ref(next, unit_id)) != "":
		return next
	if extra_action_input_error(next) != "" or not ExtraActionRules.equipment(unit_ref(next,unit_id), next["equipment_items"])["ok"]: return next
	if resource_input_error(next, unit_ref(next,unit_id)) != "": return next
	next["pending_move"] = false
	next["moved_this_action"] = false
	next["attacked_this_action"] = false
	next["selected_unit_id"] = ""
	next["last_ai_actions"] = []
	next["last_ai_action"] = {}
	next["interaction"] = "ai_resolving"
	next = BattleLoopScript.resolve_outcome(next)
	if BattleOutcome.decided(next):
		return next
	return next if not is_current_actor(next, finishing_id) else advance_current_actor(next)


static func advance_current_actor(loop: Dictionary, skipped_entry: bool = false) -> Dictionary:
	if BattleOutcome.decided(loop): return loop
	# Sole queue-advance seam for player completion, AI completion and skipped
	# unavailable slots. Caller validates/settles the action before entering here.
	var actor := unit_ref(loop, str(CoreTurnQueue.current(loop["turn_queue"]).get("id", "")))
	if extra_action_input_error(loop) != "":
		loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": extra_action_input_error(loop)}, true)
		return loop
	if Presence.living(actor):
		var resource_error := resource_input_error(loop, actor)
		if resource_error != "":
			loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": resource_error}, true)
			return loop
		if not skipped_entry and not Treasure.awaiting_handoff(loop):
			# Terrain poison runs first in the original action end (0x4454a5／0x441eb8, before
			# the 0x80000 treasure test and the extra-action query), once per completed action;
			# the status tail below then ticks it (original_poison_gas.md «地形毒»).
			var terrain_poison := PoisonGasRules.terrain(loop, actor, TerrainEdits.tiles(loop))
			if not terrain_poison.is_empty():
				terrain_poison["turn"] = int(loop["turn"])
				loop["terrain_poison"] = (loop.get("terrain_poison", []) as Array) + [terrain_poison]
		if not skipped_entry:
			var treasure := Treasure.prepare(loop, actor)
			if not treasure["ok"]:
				loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": treasure["reason"]}, true)
				return loop
			if treasure.has("state"):
				# Commit the discovery once, but keep this completed action's queue
				# lease until collection feedback/selection has finished. No extra
				# action, poison tick or resource recovery may run ahead of it.
				loop["treasures"] = treasure["state"]
				loop["settlement"] = treasure["settlement"]
				return loop
		var effect := ExtraActionRules.equipment(actor, loop["equipment_items"])
		if not effect["ok"]:
			loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": effect["reason"]}, true)
			return loop
		# Original fresh paralysis entry jumps downstream of the repeated-action
		# query. Consume this queue slot once, not two artificial Wait commands.
		if skipped_entry: clear_extra_action(loop)
		var completion := ExtraActionRules.complete(loop["extra_action"], actor["id"], effect["enabled"] and not skipped_entry)
		loop["extra_action"] = completion["state"]
		if completion["repeat"]:
			# Native first completion returns to this actor's normal decision/menu.
			# Do not tick poison, decay status, reset its kill chain or spend a slot.
			# That re-entry is phase 0, which clears the attacker global 0x4c1ce8
			# (player 0x443a36, AI 0x43f559): no scan ever reads the first half's attack.
			loop.merge({"moved_this_action": false, "attacked_this_action": false, "pending_move": false, "selected_attack": "attack", "action_attacker_id": ""}, true)
			if actor["player_commandable"]: return return_to_player(loop, actor["id"])
			loop["selected_unit_id"] = ""
			loop["interaction"] = "ai_resolving"
			return loop
	else:
		clear_extra_action(loop)
		# static-derived (original_round_display.md «Attack context»): an actor that dies
		# in its own attack (a counter) is retired by its death sequence, which calls
		# 0x407510 — the completion scan, attacker global still set — without the status
		# tail. A dead slot the queue merely skips attacked nothing and scans nothing.
		if _takes_attack_scan(loop, str(actor.get("id", ""))):
			# original_death_disposal.md «当前行动者阵亡»: its unregister 0x407720 finds the
			# current entry empty and steps the queue (0x4074a0(1), spending the next live
			# actor) before the death sequence's own 0x407510 scans and steps again — the
			# next actor loses this round's action (at a wrap: the new round's first).
			var successor_id := _step_past_dead_actor(loop)
			loop = BattleLoopScript.resolve_outcome(BattleScenarioRuleAdapter.run_event_hooks(loop, true))
			if BattleOutcome.decided(loop):
				loop["interaction"] = "battle_result"
				return loop
			if not bool(loop.get("scenario_ok", false)) or not is_current_actor(loop, successor_id):
				return loop
	if Presence.living(actor):
		var capabilities: Dictionary = ResourceRecoveryRules.effects(actor, loop["equipment_items"])["effects"]
		var tick := TurnEndRules.prepare(actor, capabilities, loop[DamageRandomStream.LOOP_KEY], int(loop["action_end_sequence"]) + 1)
		if not tick["ok"]:
			loop["scenario_ok"] = false
			loop["scenario_error"] = tick["reason"]
			loop["interaction"] = "scenario_error"
			return loop
		var after_tail := actor.duplicate(true)
		after_tail.merge(tick["changes"], true)
		if tick["receipt"]["expired"].any(func(key): return StatusEffectRules.Enhancements.FLAGS.has(key)):
			var refresh_error := ProgressionRules.refresh_input_error(after_tail, loop["equipment_items"])
			if refresh_error != "":
				loop.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": refresh_error}, true)
				return loop
			after_tail = ProgressionRules.refresh_growth_stats(after_tail, loop["equipment_items"])
		actor.merge(after_tail, true)
		loop[DamageRandomStream.LOOP_KEY] = tick["rng"]
		loop["last_action_end"] = tick["receipt"]
		loop["action_end_sequence"] = tick["receipt"]["sequence"]
		actor["kill_chain_word"] = ExperienceRules.after_action(int(actor["kill_chain_word"]))
		# static-derived (original_round_display.md): every completed action runs the
		# status tail (0x40b910, above) and then 0x407510, which scans win／fail／event
		# statuses (0x408370 → 0x44ee20) BEFORE 0x4074a0 advances the queue and bumps
		# the round at wrap. A round-N event therefore fires after round N's first
		# completed action, and wait／item／poison-tick actions are re-read too. The attack
		# cases (actCheckPlayerAttacked and siblings) read the attacker global 0x4c1ce8 in
		# this same scan, so an attack action is scanned once, after its tail.
		var actor_id := str(actor["id"])
		var attacked := _takes_attack_scan(loop, actor_id)
		loop = BattleLoopScript.resolve_outcome(BattleScenarioRuleAdapter.run_event_hooks(loop, attacked))
		if BattleOutcome.decided(loop):
			loop["interaction"] = "battle_result"
			return loop
		if not bool(loop.get("scenario_ok", false)) or not is_current_actor(loop, actor_id):
			# Script consumption retired this actor's slot and already continued.
			return loop
	loop["turn_queue"] = CoreTurnQueue.end_turn(loop["turn_queue"], queue_actors(loop))
	return finish_ai_or_continue(loop)


## The 0x407720 step for a current actor that died in its own action: the queue moves to
## the next living entry (dead slots are empty entries there), bumping the round at a wrap
## before the completion scan reads it (0x4074a0 increments 0x4c1bbc). Returns its id.
static func _step_past_dead_actor(loop: Dictionary) -> String:
	for _i in range(loop["turn_queue"]["slots"].size() + 1):
		loop["turn_queue"] = CoreTurnQueue.advance(loop["turn_queue"], queue_actors(loop))
		var id := str(CoreTurnQueue.current(loop["turn_queue"]).get("id", ""))
		if id == "" or Presence.living(unit_ref(loop, id)): break
	var round_number := int(loop["turn_queue"].get("round", 0)) + 1
	if round_number > int(loop.get("turn", 1)): loop["turn"] = round_number
	return str(CoreTurnQueue.current(loop["turn_queue"]).get("id", ""))


static func _takes_attack_scan(loop: Dictionary, actor_id: String) -> bool:
	## Consumes the action's attacker mark: true when `actor_id` attacked during the action
	## now completing. The original sets 0x4c1ce8 when an attack starts and clears it when
	## the next action starts (player 0x443a36, AI 0x43f559), so the mark never outlives
	## one completion scan and never names another actor's attack.
	var attacked := actor_id != "" and str(loop.get("action_attacker_id", "")) == actor_id
	loop["action_attacker_id"] = ""
	return attacked


## Writes `loop` in place: every caller hands over a loop it owns (the queue-advance seam
## `advance_current_actor`, which has already written it, and the outcome resolver).
static func finish_ai_or_continue(loop: Dictionary) -> Dictionary:
	var next := loop
	var round_number := int(next.get("turn_queue", {}).get("round", 0)) + 1
	if round_number > int(next.get("turn", 1)):
		# The wrap only bumps the counter; statuses are next scanned after the new
		# round's first completed action (advance_current_actor).
		next["turn"] = round_number
	next = BattleLoopScript.resolve_outcome(next)
	if BattleOutcome.decided(next):
		next["interaction"] = "battle_result"
		return next
	BattleLoopScript.maintain_script_pressure(next)
	var cur: Dictionary = CoreTurnQueue.current(next.get("turn_queue", {}))
	var cur_id := str(cur.get("id", ""))
	if cur_id == "":
		next["interaction"] = "idle"
		return next
	var actor: Dictionary = unit_ref(next, cur_id)
	if not Presence.living(actor):
		return advance_current_actor(next)
	if bool(actor.get("player_commandable", false)):
		return return_to_player(next, cur_id)
	next["interaction"] = "ai_resolving"
	return next


static func return_to_player(loop: Dictionary, unit_id: String) -> Dictionary:
	var next := copy(loop)
	var entry := ActionEntryRules.prepare(unit_ref(next, unit_id))
	if not entry["ok"]:
		next.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": entry["reason"]}, true)
		return next
	next["selected_unit_id"] = unit_id
	next["interaction"] = "action_menu"
	next["moved_this_action"] = false
	next["attacked_this_action"] = false
	next["pending_move"] = false
	if entry["skip"]:
		next["selected_unit_id"] = ""
		next["interaction"] = "ai_resolving"
		next["command_menu"] = {"commands": []}
		return next
	next["command_menu"] = menu_for_unit(next, unit_id)
	return next


static func unit_coords(loop: Dictionary) -> Dictionary:
	var out := {}
	for unit_value in loop.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if not Presence.living(unit):
			continue
		out[str(unit.get("id", ""))] = unit.get("coord", Vector2i.ZERO)
	return out


static func unit(loop: Dictionary, unit_id: String) -> Dictionary:
	## Read-only public lookup for scene presentation and input gates.
	## BattlePlayLoop is the single mutable battle-state owner.
	var value := unit_ref(loop, unit_id)
	return value.duplicate(true) if not value.is_empty() else {}


## The original's per-actor "known" byte (0x4c6d80[index], saved with the game): the
## identity strip prints ??? for a unit until it is set. pmPlayer actors are born known
## (0x407e01); every other unit becomes known when any attack or skill — player or AI, an
## ally NPC's included — takes it as a target (0x430020 at target confirmation:
## 0x444388／0x445166／0x44544b player weapon, 0x440279 AI weapon, 0x441878／0x441b82／
## 0x441e8c skills, 0x442b3c／0x442ed5／0x443262 cast sequence), or when it dies (0x43ef5b).
## A counter hit does not reveal (the counter series pushes no target; emulator-measured).
## docs/evidence_packets/static_reverse/original_identity_bar.md
## The byte is indexed by the PLAYERS template row (obj+0xa2), which every unit of that row
## shares (runtime-measured 2026-09-26: one 021 dies, all five 021 read known). The remake
## keeps recording the marked unit ids; the judgement asks whether any known unit shares
## the actor_id, so the storage and checkpoint v3 key are unchanged. `known_ids` reads an
## earlier snapshot of the set instead (an exchange receipt's `strip_known_ids`).
static func unit_known(loop: Dictionary, unit_id: String, known_ids: Variant = null) -> bool:
	var target := unit_ref(loop, unit_id)
	if target.is_empty():
		return false
	if ActorRoleRules.side_mask(target) == ActorRoleRules.SIDE_PLAYER:
		return true
	var known: Array = loop["known_unit_ids"] if known_ids == null else known_ids
	if known.has(unit_id):
		return true
	var actor_id := str(target.get("actor_id", ""))
	if actor_id == "":
		return false
	for known_id in known:
		if str(unit_ref(loop, str(known_id)).get("actor_id", "")) == actor_id:
			return true
	return false


static func mark_known(loop: Dictionary, unit_id: String) -> void:
	if unit_id == "" or unit_ref(loop, unit_id).is_empty():
		return
	var known: Array = loop["known_unit_ids"]
	if not known.has(unit_id):
		known.append(unit_id)


static func menu_for_unit(loop: Dictionary, unit_id: String) -> Dictionary:
	var actor := unit_ref(loop, unit_id)
	var menu := product_command_menu(
		CoreTurnQueue.build_command_menu(not special_options(loop, unit_id).is_empty(), magic_position_error(loop, actor) == "" and not magic_options(loop, unit_id).is_empty()),
		bool(loop.get("moved_this_action", false)),
		bool(loop.get("attacked_this_action", false))
	)
	for command in menu["commands"]:
		if command["command"] == "special":
			command["enabled"] = special_page_available(loop, unit_id)
		elif command["command"] == "attack":
			var pattern := weapon_pattern(loop, actor)
			command["enabled"] = pattern.get("ok", false) and not pattern.get("offsets", []).is_empty()
	menu["unit_id"] = unit_id
	return menu


static func product_command_menu(source_menu: Dictionary, moved: bool, attacked: bool) -> Dictionary:
	var menu := source_menu.duplicate(true)
	var commands: Array = []
	for cmd_value in menu.get("commands", []):
		var cmd: Dictionary = cmd_value
		var name := str(cmd.get("command", ""))
		if name not in IMPLEMENTED_COMMANDS:
			continue
		cmd["implemented"] = true
		cmd["enabled"] = true
		if not ActionBudgetRules.command_available(name, moved, attacked):
			continue
		commands.append(cmd)
	menu["commands"] = commands
	menu["product_surface"] = "implemented_commands_only"
	return menu


static func _command_ids(loop: Dictionary) -> Array:
	var ids: Array = []
	for cmd_value in (loop.get("command_menu", {}) as Dictionary).get("commands", []):
		if typeof(cmd_value) == TYPE_DICTIONARY:
			ids.append(str((cmd_value as Dictionary).get("command", "")))
	return ids


static func queue_actors(loop: Dictionary) -> Array:
	return CoreTurnQueue.queue_actors(loop.get("units", []), Presence.living)


static func _alive_units(loop: Dictionary) -> Array:
	var out: Array = []
	for unit_value in loop.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if Presence.living(unit):
			out.append(unit)
	return out


static func unit_ref(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit_value in loop.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("id", "")) == unit_id:
			return unit
	return {}


static func set_unit_coord(loop: Dictionary, unit_id: String, coord: Vector2i) -> void:
	var units: Array = loop.get("units", [])
	for i in range(units.size()):
		if typeof(units[i]) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = units[i]
		if str(unit.get("id", "")) == unit_id:
			unit["coord"] = coord
			unit["grid_coord"] = coord
			units[i] = unit
			loop["units"] = units
			return


static func set_unit_hp(loop: Dictionary, unit_id: String, hp: int) -> void:
	var units: Array = loop.get("units", [])
	for i in range(units.size()):
		if typeof(units[i]) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = units[i]
		if str(unit.get("id", "")) == unit_id:
			unit["hp"] = hp
			units[i] = unit
			loop["units"] = units
			return


static func set_unit_defeated(loop: Dictionary, unit_id: String, defeated: bool) -> void:
	var units: Array = loop.get("units", [])
	for i in range(units.size()):
		if typeof(units[i]) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = units[i]
		if str(unit.get("id", "")) == unit_id:
			unit["defeated"] = defeated
			if defeated:
				mark_known(loop, unit_id)
				var had_buff := (int(unit["status_flags"]) & 0x70) != 0
				if loop["extra_action"]["owner_id"] == unit_id: clear_extra_action(loop)
				unit["hp"] = 0
				unit["status_flags"] = 0
				unit["status_counters"] = StatusEffectRules.cleared_counters()
				if had_buff and ProgressionRules.refresh_input_error(unit, loop["equipment_items"]) == "":
					unit.merge(ProgressionRules.refresh_growth_stats(unit, loop["equipment_items"]), true)
				unit["hit_bonus_accum"] = 0
				unit["action_ready"] = false
				unit["ai_call_target_id"] = ""
				unit["kill_chain_word"] = 0
				if unit.has("stamina"): unit["stamina"] = 0
			units[i] = unit
			loop["units"] = units
			if defeated: AI.prune_ai_calls(loop)
			return


static func is_current_actor(loop: Dictionary, unit_id: String) -> bool:
	var cur: Dictionary = CoreTurnQueue.current(loop.get("turn_queue", {}))
	# Queue identity also gates the common outcome/cleanup entry. An actor at
	# zero HP may still own that entry until defeat resolves; live action entry
	# separately rejects death. A retired actor has no remaining queue identity.
	return unit_id != "" and str(cur.get("id", "")) == unit_id and not unit_ref(loop, unit_id).get("departed", false)


static func are_enemies(a: Dictionary, b: Dictionary) -> bool:
	# Side bits of the installed player_mode (pmPlayerEnemy villagers are hostile to no
	# camp, pmNPC units to both); units without one keep their role-implied side.
	return ActorRoleRules.hostile(a, b)


static func skill_input_error(loop: Dictionary, actor: Dictionary) -> String:
	var resource_error := resource_input_error(loop, actor)
	if resource_error != "": return resource_error
	var extra_error := extra_action_input_error(loop)
	if extra_error != "": return extra_error
	var extra_effect := ExtraActionRules.equipment(actor, loop["equipment_items"])
	if not extra_effect["ok"]: return extra_effect["reason"]
	var traversal_error := TraversalRules.actor_error(actor, loop["skill_book"])
	if traversal_error != "": return traversal_error
	var mobility := MobilityRules.prepare(actor, loop["equipment_items"])
	if not mobility["ok"]: return mobility["reason"]
	var sequence := Combat.attack_count(loop, actor)
	if not sequence["ok"]: return sequence["reason"]
	var status_error := StatusEffectRules.input_error(actor)
	if status_error != "":
		return status_error
	var stamina_error := StaminaRules.input_error(actor, loop["equipment_items"])
	if stamina_error != "": return stamina_error
	var experience_error := ExperienceRules.input_error(loop, actor, true)
	if experience_error != "": return experience_error
	var requests: Array = []
	for id in loop["skill_book"]["skills"]:
		if SkillResolutionRules.ownership_error(actor, id, loop["skill_book"]) == "":
			requests.append([id, skill_fields(loop, id)])
	for request in requests:
		var quote := SkillResolutionRules.available(actor, request[0], request[1], loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])
		if not quote["ok"] and quote["reason"] not in ["insufficient_stamina", "insufficient_mp", "skill_not_owned", "caster_unavailable", "caster_paralyzed", "magic_disabled_by_status"]:
			return str(quote["reason"])
	return ""


## Whether 特殊技 opens the skill page: the unit owns a special and has not attacked this
## action. Affordability does not gate the page (a row 氣力 cannot pay is shown disabled);
## can_use_special is the "some special can be cast now" test.
static func special_page_available(loop: Dictionary, unit_id: String) -> bool:
	return not bool(loop.get("attacked_this_action", false)) and not special_options(loop, unit_id).is_empty()


static func can_use_special(loop: Dictionary, unit_id: String) -> bool:
	return not bool(loop.get("attacked_this_action", false)) and special_options(loop, unit_id).any(func(option): return option["quote"]["ok"])


static func settle_action(loop: Dictionary, operation: String, give_used: bool = false) -> Dictionary:
	var result := ActionBudgetRules.outcome(operation, give_used)
	if result["kind"] == "invalid":
		return loop
	loop.merge(result["changes"], true)
	if result["kind"] == "end_action":
		return begin_wait_resolution(loop)
	var id := str(loop.get("selected_unit_id", ""))
	if id != "":
		loop["command_menu"] = menu_for_unit(loop, id)
	return loop


static func extra_action_input_error(loop: Dictionary) -> String:
	var error := ExtraActionRules.state_error(loop.get("extra_action"), str(CoreTurnQueue.current(loop.get("turn_queue", {})).get("id", "")), BattleOutcome.decided(loop))
	if error != "": return error
	if loop["extra_action"]["pending"]:
		var actor := unit_ref(loop, loop["extra_action"]["owner_id"])
		if not Presence.living(actor): return "unavailable_extra_action_owner"
	return ""


static func clear_extra_action(loop: Dictionary) -> void:
	loop["extra_action"] = ExtraActionRules.empty(int(loop["extra_action"]["sequence"]))


static func resource_input_error(loop: Dictionary, actor: Dictionary) -> String:
	var stat_error := ProgressionRules.enhancement_profile_error(actor, loop["equipment_items"])
	if stat_error != "": return stat_error
	var error := TurnEndRules.state_error(loop)
	if error != "": return error
	var capabilities := ResourceRecoveryRules.effects(actor, loop["equipment_items"])
	if not capabilities["ok"]: return capabilities["reason"]
	var casting := StatusApplicationRules.modifiers(actor, loop["skill_book"], loop["equipment_items"])
	if not casting["ok"]: return casting["reason"]
	var position := PositionCapabilities.effects(actor, loop["skill_book"], loop["equipment_items"])
	if not position["ok"]: return position["reason"]
	var weapon := WeaponEffects.effects(actor, loop["equipment_items"])
	if not weapon["ok"]: return weapon["reason"]
	return ResourceRecoveryRules.health_error(actor)


## The one presentation input the rules read: the camera's top-left in map pixels (the
## original's 0x4c091c／0x4c0920, which 打人閃電 reads), stamped in place on the current loop
## before a rule operation. Not rule state — rules copy it through and never change it — so
## it bypasses the scene's apply_loop (no rule operation, no mirror sync, same dictionary).
static func stamp_presentation_view(loop: Dictionary, view: Vector2i) -> void:
	loop[LoopKeys.PRESENTATION_VIEW] = view


## Settlement (BattleLoopRewards): pending-loot interaction and growth allocation.
static func loot_waiting(loop: Dictionary) -> bool:
	return BattleLoopRewards.loot_waiting(loop)


static func loot_recipients(loop: Dictionary) -> Array:
	return BattleLoopRewards.loot_recipients(loop)


static func claim_reward(loop: Dictionary, sequence: int, revision: int, entry_id: String, recipient_id: String, slot: int = -1, expected_code: int = 0) -> Dictionary:
	return BattleLoopRewards.claim_reward(loop, sequence, revision, entry_id, recipient_id, slot, expected_code)


static func finish_rewards(loop: Dictionary, sequence: int, revision: int, abandon: bool = false, defer: bool = false) -> Dictionary:
	return BattleLoopRewards.finish_rewards(loop, sequence, revision, abandon, defer)


static func reopen_rewards(loop: Dictionary) -> Dictionary:
	return BattleLoopRewards.reopen_rewards(loop)


static func allocate_growth(loop: Dictionary, unit_id: String, allocation: Dictionary) -> Dictionary:
	return BattleLoopRewards.allocate_growth(loop, unit_id, allocation)


## Internal seams of the extracted modules that Checkpoint, GrowthCampaignProgress and
## BattleSceneRuntime reach through this facade. Tests reach the other module seams on the
## module itself (`const LoopAI = preload(BattleLoopAI)` …).
static func reward_input_error(loop: Dictionary) -> String:
	return BattleLoopRewards.reward_input_error(loop)


static func resolve_outcome(next: Dictionary) -> Dictionary:
	return BattleLoopScript.resolve_outcome(next)


## AI turn driving (BattleLoopAI): the stepped AI entry.
static func step_ai_turn(loop: Dictionary, rng: Variant = null) -> Dictionary:
	return AI.step_ai_turn(loop, rng)


## Combat commit (BattleLoopCombat): the strike-count read.
static func attack_count(loop: Dictionary, actor: Dictionary) -> Dictionary:
	return Combat.attack_count(loop, actor)


## Inventory and equipment (BattleLoopInventory): player Use／Drop／Give／Equip and the
## battle equipment carry.
static func use_item(loop: Dictionary, item_code: String, target_id: String = "", inventory_index: int = -1) -> Dictionary:
	return BattleLoopInventory.use_item(loop, item_code, target_id, inventory_index)


static func discard_item(loop: Dictionary, item_code: String, inventory_index: int = -1) -> Dictionary:
	return BattleLoopInventory.discard_item(loop, item_code, inventory_index)


static func recovery_target_ids(loop: Dictionary) -> Array:
	return BattleLoopInventory.recovery_target_ids(loop)


static func begin_give(loop: Dictionary) -> Dictionary:
	return BattleLoopInventory.begin_give(loop)


static func give_target_ids(loop: Dictionary) -> Array:
	return BattleLoopInventory.give_target_ids(loop)


static func confirm_give(loop: Dictionary, target_id: String, index: int, expected_code: int, target_index: int, expected_return: int, revision: int) -> Dictionary:
	return BattleLoopInventory.confirm_give(loop, target_id, index, expected_code, target_index, expected_return, revision)


static func finish_give(loop: Dictionary, revision: int) -> Dictionary:
	return BattleLoopInventory.finish_give(loop, revision)


static func change_equipment(loop: Dictionary, slot: String, inventory_index: int, expected_code: int) -> Dictionary:
	return BattleLoopInventory.change_equipment(loop, slot, inventory_index, expected_code)


static func apply_battle_equipment_carry(loop: Dictionary, carry: Dictionary) -> Dictionary:
	return BattleLoopInventory.apply_battle_equipment_carry(loop, carry)
