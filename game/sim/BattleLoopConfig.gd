extends RefCounted
## The battle loop dictionary carries two kinds of keys: read-only configuration that
## BattlePlayLoop.create() loads once (terrain tiles, the skill book, the equipment
## catalog, AI profiles, script sources …) and the mutable state the rules advance. Rules
## are `f(loop) -> loop` pure functions that never write their input; `copy` is the one way
## to copy a whole loop, deep-copying the state and sharing every CONFIG_SHARED block by
## reference. Contract: docs/architecture/BATTLE_CONFIG_STATE.md.
## provenance:
##   rules: remake-invented (configuration／state key partition of the remake's loop dictionary; no original counterpart)

## Always present after a successful create(); BattleCheckpoint digests them in this order.
## `escape_zone` is not here although create() fills it: WinfailScenarioRules._refresh_objective
## re-derives it from the armed win statuses every round, so it is state and is saved.
const CONFIG_KEYS := ["scenario_path", "rule_adapter", "player_unit_id", "map_size", "tiles", "skill_rules", "skill_target_data", "skill_book", "ai_profiles", "consumables", "equipment_items", "attack_patterns", "weapon_ranges", "reward_data", "events", "reinforcement_spawn_cells", "turn_end_policy", "stat_refresh_policy", "item_use_policy", "departure_policy"]
## Source blocks a `_load_*` stage or the rule adapter stores for some scenarios only
## (the compiled winfail program and the job-up tables are the adapter's read-only inputs;
## BattleCheckpoint.configuration digests the program for winfail battles).
const CONFIG_SOURCE_KEYS := ["script_wait_source", "entry_growth_data", "script_actor_source", "treasure_source", "script_presentation_source", "winfail_script_rules", "job_up_templates", "job_up_targets"]
## Every key `copy` shares by reference and the test-time freeze re-hashes. A new
## read-only input registers here or it keeps being deep-copied with the state.
const CONFIG_SHARED := CONFIG_KEYS + CONFIG_SOURCE_KEYS

## Test-time freeze registry (tests/support/TestSuite.gd assert_config_frozen): while
## enabled, create() records a hash of every CONFIG_SHARED value it produced so a suite
## can prove afterwards that no rule wrote into a shared block. Off in the product path.
static var freeze_enabled := false
static var _frozen: Array = []
## Whole-loop copies made since a diagnostic last reset it (tests/measure_loop_copy.gd
## reads it per round and per lookahead decision); nothing in the product path reads it.
static var copy_count := 0


## State keys deep-copied, CONFIG_SHARED values shared by reference.
static func copy(loop: Dictionary) -> Dictionary:
	copy_count += 1
	var next := {}
	for key in loop:
		var value: Variant = loop[key]
		if CONFIG_SHARED.has(key) or (typeof(value) != TYPE_DICTIONARY and typeof(value) != TYPE_ARRAY):
			next[key] = value
		else:
			next[key] = value.duplicate(true)
	return next


## True when every non-configuration key compares equal: two loops of one battle share
## their configuration, so they can only differ in state.
static func same_state(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if CONFIG_SHARED.has(key):
			continue
		if not right.has(key) or left[key] != right[key]:
			return false
	return true


static func freeze(loop: Dictionary) -> void:
	for key in CONFIG_SHARED:
		if loop.has(key):
			_frozen.append({"key": key, "value": loop[key], "hash": hash(loop[key])})


## Re-hashes every configuration block recorded since the registry was last cleared and
## returns the keys whose content changed; clears the registry.
static func thaw() -> Array:
	var changed: Array = []
	for entry in _frozen:
		if hash(entry["value"]) != int(entry["hash"]) and not changed.has(entry["key"]):
			changed.append(entry["key"])
	_frozen = []
	return changed
