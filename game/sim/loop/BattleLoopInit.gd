extends RefCounted
## Battle loop initialization: `create()` builds the one loop dictionary from a scenario —
## the initial state skeleton (`_initial_loop`), then the ordered `_load_*` stages that read
## the tracked content (terrain, roster contract, skill book, AI profiles, progression,
## inventory catalog, rewards, script templates, treasures, attack ranges, script payload,
## scenario rules, opening timeline, script waits). Every stage writes into the same loop
## and returns a `scenario_error` reason or "" — there is no fallback battle. The roster
## hand-off seams that run before `begin_battle` (`initialize_roster_growth`,
## `apply_campaign_carry`) live here too. The module owns no state; BattlePlayLoop
## forwards to it and remains the single mutable battle-state owner.
## provenance:
##   rules: static-derived content/generated/hsl/static/hsl01/core_logic.json
##   rules: resource-derived content/generated/hsl/skills/initial_book.json
##   rules: resource-derived content/generated/hsl/ai/profiles.json
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: remake-invented
##     (create() stage order and scenario_error intake contract; reward_seed seeds the damage／global streams for pure
##     callers — docs/architecture/BATTLE_CONFIG_STATE.md)
##   rules: static-derived docs/evidence_packets/static_reverse/original_random_position.md

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const WrdTerrainTiles = preload("res://game/sim/WrdTerrainTiles.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const ScriptWait = preload("res://game/sim/ScriptWaitRules.gd")
const ReinforcementGrowth = preload("res://game/sim/ReinforcementGrowthRules.gd")
const InitialRosterGrowthRules = preload("res://game/sim/InitialRosterGrowthRules.gd")
const ItemResolutionRules = preload("res://game/sim/ItemResolutionRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const ExtraActionRules = preload("res://game/sim/ExtraActionRules.gd")
const TurnEndRules = preload("res://game/sim/TurnEndRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const UnitSchema = preload("res://game/sim/UnitSchema.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const TraversalRules = preload("res://game/sim/ActorTraversalRules.gd")
const ActorInitializationRules = preload("res://game/sim/ActorInitializationRules.gd")
const ScriptActorCreationRules = preload("res://game/sim/ScriptActorCreationRules.gd")
const Treasure = preload("res://game/sim/TreasureRules.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")


## `global_state`: the global stream words the battle starts from (the scene passes the
## process's live stream, GlobalRandomStream.session()); [] seeds them from reward_seed,
## so a pure caller (tests, autoplay, exporters) keeps a fixed stream per seed.
static func create(units: Array = [], terrain_path: String = "", scenario: Dictionary = {}, reward_seed: int = 1, global_state: Array = []) -> Dictionary:
	# The scenario is the caller's (BattleScenario.load_file of a content/battles file or
	# a dictionary built in memory); there is no default battle to fall back to.
	var active_scenario := scenario
	if active_scenario.is_empty():
		return _fail(_initial_loop({}, [], {}, reward_seed, global_state), "missing_scenario")
	# The contract (content/schema/battle.schema.json) is checked once per document:
	# BattleScenario.load_file marks what it validated and defaulted; a dictionary built
	# in memory is checked here so the stages below read only contract-shaped input.
	if active_scenario.get("contract") != BattleScenario.BATTLE_CONTRACT:
		var violation := BattleScenario.battle_error(active_scenario)
		if violation != "":
			return _fail(_initial_loop(active_scenario, [], {}, reward_seed, global_state), "battle_schema:" + violation)
		active_scenario = BattleScenario.with_defaults(active_scenario)
	var roster: Array = units.duplicate(true) if not units.is_empty() else BattleScenario.units(active_scenario)
	var resolved_terrain_path := terrain_path
	if resolved_terrain_path == "":
		resolved_terrain_path = BattleScenario.resource_path(active_scenario, "terrain")
	if resolved_terrain_path == "":
		resolved_terrain_path = WrdTerrainTiles.DEFAULT_PATH
	var terrain: Dictionary = WrdTerrainTiles.load_tiles(resolved_terrain_path, active_scenario.get("terrain_overrides", []))
	var loop := _initial_loop(active_scenario, roster, terrain, reward_seed, global_state)
	# Intake carries the scenario-side inputs that later stages consume but that are
	# not loop state (the caller-supplied roster flag, the progression table, the
	# starting inventories, a fixture's stamina pin and the script payload).
	var intake := {"terrain": terrain, "caller_roster": not units.is_empty(), "reward_seed": reward_seed}
	for stage in [
		_load_terrain, _load_roster_contract, _load_skill_targeting,
		_load_skill_book, _load_growth_lifecycle, _load_ai_profiles, _load_entry_growth, _load_progression,
		_load_initial_stamina, _load_inventory_catalog, _load_rewards, _check_inventory_catalog,
		_prepare_roster, _check_roster_inputs, _load_script_actor_templates, _load_treasures, _rebuild_queue,
		_load_attack_ranges, _load_script_payload, _load_scenario_rules, _initialize_script_state,
		_load_script_walk_source, _load_opening_timeline, _load_opening_story_state, _load_script_waits,
	]:
		var reason: String = stage.call(loop, active_scenario, intake)
		if reason != "":
			return _fail(loop, reason)
	if BattleLoopConfig.freeze_enabled:
		BattleLoopConfig.freeze(loop)
	return loop


## Every scenario-side rejection goes through here: the loop stays a complete
## dictionary (summary(), the runtime and the tests read the rest of it) and only
## the three intake fields change.
static func _fail(loop: Dictionary, reason: String) -> Dictionary:
	loop["scenario_ok"] = false
	loop["interaction"] = "scenario_error"
	loop["scenario_error"] = reason
	return loop


static func _initial_loop(active_scenario: Dictionary, roster: Array, terrain: Dictionary, reward_seed: int, global_state: Array = []) -> Dictionary:
	var command_flags := BattleScenario.command_flags(active_scenario)
	var queue_actors: Array = []
	for unit_value in roster:
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("defeated", false)):
			continue
		queue_actors.append({
			"id": str(unit.get("id", "")),
			"live_speed": int(unit.get("live_speed", unit.get("speed", 0))),
			"action_ready": bool(unit.get("action_ready", true)),
			"registered_slot": CoreTurnQueue.registration_slot(unit),
		})
	var queue: Dictionary = CoreTurnQueue.rebuild(queue_actors)
	return {
		"schema": "hsl_first_scene_play_loop.v1",
		"scenario_schema": str(active_scenario.get("schema", "")),
		"scenario_path": str(active_scenario.get("path", "")),
		"scenario_ok": bool(active_scenario.get("ok", false)),
		"rule_adapter": BattleScenarioRuleAdapter.adapter_id(active_scenario),
		"mechanics_priority": "original_fidelity",
		"units": roster,
		"departure_policy": Presence.POLICY,
		"departure_sequence": 0,
		"last_departure": {},
		"script_wait_source": {"policy": ScriptWait.POLICY, "initial": []},
		"script_wait_cursor": 0,
		"last_script_wait": {},
		# The global stream AI decisions, NPC level adjustment (0x40e870), birth carry (0x407c40),
		# kill drops (0x44f580), random positions and the opening's slot shuffle draw from
		# (0x458c80). Not saved: a checkpoint load keeps the live words (BattleCheckpoint.restored).
		GlobalRandomStream.LOOP_KEY: global_state.duplicate() if GlobalRandomStream.valid(global_state) else GlobalRandomStream.seeded(reward_seed),
		"tiles": terrain.get("tiles", {}),
		"terrain_edits": [],
		"map_size": terrain.get("map_size", Vector2i(24, 24)),
		"terrain_ok": bool(terrain.get("ok", false)),
		"terrain_blocking_count": int(terrain.get("blocking_count", 0)),
		"turn_queue": queue,
		"interaction": "idle",
		"selected_unit_id": "",
		"pending_move": false,
		"pending_move_from": Vector2i.ZERO,
		"moved_this_action": false,
		"attacked_this_action": false,
		"give_session": {},
		"item_revision": 0,
		"item_use_policy": ItemResolutionRules.POLICY,
		# The one damage stream items, exchanges, casts and the turn-end tail draw from. New game
		# (0x42ca47): word0 = t, word1 = ~t; a campaign carry replaces it (apply_campaign_carry).
		DamageRandomStream.LOOP_KEY: DamageRandomStream.seeded(reward_seed),
		"item_use_sequence": 0,
		"last_item_use": {},
		"extra_action": ExtraActionRules.empty(),
		"turn_end_policy": TurnEndRules.POLICY,
		"stat_refresh_policy": ProgressionRules.JobStats.MODEL,
		"action_end_sequence": 0,
		"last_action_end": {},
		"gold": 0,
		"rewarded_unit_ids": [],
		"known_unit_ids": [],
		"settlement": {},
		"last_attack": {},
		"action_attacker_id": "",
		"last_command_reject": {},
		"last_ai_actions": [],
		"battle_outcome": {},
		"command_menu": BattlePlayLoop._product_command_menu(
			CoreTurnQueue.build_command_menu(
				bool(command_flags.get("has_special", false)),
				bool(command_flags.get("has_magic", false))
			),
			false,
			false
		),
		"formula_source": "core_logic",
		"opening_skeleton_status": "owned_by_BattleSceneRuntime",
	}


static func _read_json(path: String) -> Variant:
	if path == "" or not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func _load_terrain(_loop: Dictionary, _scenario: Dictionary, intake: Dictionary) -> String:
	var terrain: Dictionary = intake["terrain"]
	if not bool(terrain.get("ok", false)):
		return str(terrain.get("error", "invalid_terrain"))
	return ""


static func _load_roster_contract(loop: Dictionary, _scenario: Dictionary, intake: Dictionary) -> String:
	# The scenario roster is JSON entering the loop: it must match the shared unit
	# contract before any rule reads it. A caller-supplied roster is already in-memory
	# state (tests, sandboxes) and stays the caller's responsibility.
	if intake["caller_roster"]:
		return ""
	var roster_error := UnitSchema.roster_error(loop["units"])
	if roster_error != "":
		return "unit_schema:" + roster_error
	return ""


static func _load_skill_targeting(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	var targeting: Variant = _read_json(ContentPaths.SKILL_TARGETING)
	if not targeting is Dictionary:
		return "missing_skill_target_data"
	loop["skill_target_data"] = targeting
	return ""


static func _load_skill_book(loop: Dictionary, scenario: Dictionary, _intake: Dictionary) -> String:
	var skill_book: Variant = _read_json(ContentPaths.SKILL_BOOK)
	if not skill_book is Dictionary or skill_book.get("schema") != "hsl_initial_supported_skills.v1":
		return "missing_skill_book"
	if scenario.has("training_skill_grants"):
		if loop["rule_adapter"] != "development_battle" or loop["scenario_schema"] != "hsl_development_battle.v1":
			return "training_grants_outside_trial"
		var training := preload("res://game/sim/DevelopmentBattleRules.gd").training_book(scenario, skill_book)
		if not training["ok"]:
			return str(training["reason"])
		skill_book = training["book"]
	loop["skill_book"] = skill_book
	return ""


static func _load_growth_lifecycle(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	var learning_data: Variant = _read_json(ContentPaths.GROWTH_LIFECYCLE)
	if not learning_data is Dictionary or learning_data.get("schema") != "hsl_growth_lifecycle.v1":
		return "missing_growth_lifecycle_data"
	loop["skill_book"]["learning"] = learning_data
	return ""


static func _load_ai_profiles(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	var ai_profiles: Variant = _read_json(ContentPaths.AI_PROFILES)
	if not ai_profiles is Dictionary or ai_profiles.get("schema") != "hsl_ai_profiles.v1":
		return "missing_ai_profiles"
	loop["ai_profiles"] = ai_profiles
	return ""


static func _load_entry_growth(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	var entry_data: Variant = _read_json(ContentPaths.ENTRY_GROWTH)
	if not entry_data is Dictionary or entry_data.get("schema") != "hsl_entry_growth_sources.v1":
		return "missing_entry_growth_data"
	loop["entry_growth_data"] = entry_data
	return ""


static func _load_progression(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	var progression: Variant = _read_json(BattleScenario.resource_path(scenario, "progression"))
	if not progression is Dictionary or not progression.get("actors") is Dictionary:
		return "missing_progression_data"
	intake["progression"] = progression["actors"]
	loop["selected_attack"] = "attack"
	return ""


static func _load_initial_stamina(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	loop["skill_rules"] = scenario["skill_rules"]
	# Every actor starts at its PLAYERS template stamina (ActorInitializationRules.prepare);
	# only a development fixture pins them all with skill_rules.initial_stamina (-1: no pin).
	intake["initial_stamina"] = -1
	if loop["skill_rules"].has("initial_stamina"):
		var pinned := SkillResourceRules._integer(loop["skill_rules"]["initial_stamina"])
		if pinned < 0 or pinned > StaminaRules.CAP:
			return "invalid_initial_stamina"
		intake["initial_stamina"] = pinned
	return ""


static func _load_inventory_catalog(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	# The catalog's shape is judged by _check_inventory_catalog after the reward source
	# (that order is the existing failure order); here it only has to be a dictionary.
	var items: Variant = _read_json(BattleScenario.resource_path(scenario, "consumables"))
	intake["items"] = items if items is Dictionary else {}
	loop["consumables"] = intake["items"].get("items", {})
	loop["equipment_items"] = EquipmentCatalog.items()
	return ""


static func _load_rewards(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	var rewards: Variant = _read_json(ContentPaths.BATTLE_REWARDS)
	if not rewards is Dictionary or BattleRewardRules.data_error(rewards, loop["units"]) != "":
		return "invalid_reward_source"
	loop["reward_data"] = rewards
	return ""


static func _check_inventory_catalog(loop: Dictionary, _scenario: Dictionary, intake: Dictionary) -> String:
	if intake["items"].get("schema") != "hsl_first_battle_consumables.v4" or not intake["items"].get("initial_inventory") is Dictionary or loop["equipment_items"].is_empty():
		return "invalid_inventory_catalog"
	return ""


static func _prepare_roster(loop: Dictionary, _scenario: Dictionary, intake: Dictionary) -> String:
	for index in range(loop["units"].size()):
		var prepared := ActorInitializationRules.prepare(loop["units"][index], loop["skill_book"], loop["ai_profiles"], intake["progression"], intake["items"]["initial_inventory"], loop["equipment_items"], intake["initial_stamina"])
		if not prepared["ok"]:
			return str(prepared["reason"])
		loop["units"][index] = prepared["actor"]
	return ""


static func _check_roster_inputs(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	for actor in loop["units"]:
		var placement_error := TraversalRules.placement_error(actor, loop["units"], loop["tiles"], loop["map_size"], true)
		if placement_error != "":
			return placement_error
		var resource_error := BattlePlayLoop._skill_input_error(loop, actor)
		if resource_error == "": resource_error = CoreCombatRules.input_error(actor)
		if resource_error != "":
			return resource_error
		if actor.has("growth_profile"):
			var refresh_error := ProgressionRules.refresh_input_error(actor, loop["equipment_items"])
			if refresh_error != "":
				return refresh_error
	return ""


static func _load_script_actor_templates(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	if not scenario.has("script_actor_templates"):
		return ""
	var source_error := ScriptActorCreationRules.source_error(scenario["script_actor_templates"])
	if source_error != "":
		return source_error
	var source := {}
	for symbol in scenario["script_actor_templates"]:
		var spec: Dictionary = scenario["script_actor_templates"][symbol].duplicate(true)
		var normalized := BattleScenario.units({"playable_units": [spec["actor"]]})
		var template_error := UnitSchema.input_error(normalized[0], {}, "script_actor_templates." + str(symbol) + ".actor")
		if template_error != "":
			return "unit_schema:" + template_error
		if spec.has("insert_skip"):
			# The assembler declared this scripted install as an explicit skip
			# (level 15's 咕嚕 008 keeps the source 3CellCircle weapon the reviewed
			# catalog refuses). Keep the raw template; the insert records the skip
			# instead of initializing a playable substitute.
			spec["actor"] = normalized[0]
		else:
			var prepared := ActorInitializationRules.prepare(normalized[0], loop["skill_book"], loop["ai_profiles"], intake["progression"], intake["items"]["initial_inventory"], loop["equipment_items"], intake["initial_stamina"])
			if not prepared["ok"]:
				return str(prepared["reason"])
			spec["actor"] = prepared["actor"]
			var error := BattlePlayLoop._skill_input_error(loop, spec["actor"])
			if error == "": error = CoreCombatRules.input_error(spec["actor"])
			if error != "":
				return error
		source[symbol] = spec
	loop["script_actor_source"] = {"policy": "source_script_actor_v1", "templates": source}
	loop["script_actor_transactions"] = []
	return ""


static func _load_treasures(loop: Dictionary, scenario: Dictionary, _intake: Dictionary) -> String:
	if not scenario.get("resources", {}).has("treasures"):
		return ""
	var data: Variant = _read_json(str(scenario["resources"]["treasures"]))
	var initialized := Treasure.initialize(data if data is Dictionary else {}, int(scenario.get("level", 0)), loop["equipment_items"], loop["map_size"])
	if not initialized["ok"]:
		return str(initialized["reason"])
	loop["treasure_source"] = initialized["source"]
	loop["treasures"] = initialized["state"]
	return ""


static func _rebuild_queue(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	# Initial queue is built from refreshed speeds. Mid-round changes still wait
	# for the ordinary queue wrap; this seam is initialization only.
	# The enemies' birth carry rolls with their level adjustment (InitialRosterGrowthRules).
	loop["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop._queue_actors(loop))
	return ""


static func _load_attack_ranges(loop: Dictionary, scenario: Dictionary, _intake: Dictionary) -> String:
	var range_manifest: Variant = _read_json(BattleScenario.resource_path(scenario, "attack_ranges"))
	if typeof(range_manifest) != TYPE_DICTIONARY or not range_manifest.has("patterns") or not range_manifest.has("weapons"):
		return "missing_attack_ranges"
	loop["attack_patterns"] = range_manifest["patterns"]
	loop["weapon_ranges"] = range_manifest["weapons"]
	for unit in loop["units"]:
		var weapon_id := str(int(unit.get("weapon_code", -1)))
		if not loop["weapon_ranges"].has(weapon_id) or not loop["attack_patterns"].has(str(loop["weapon_ranges"].get(weapon_id, ""))):
			return "missing_unit_attack_range"
	return ""


static func _load_script_payload(_loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	var script_key := BattleScenarioRuleAdapter.script_resource_key(scenario)
	var script: Variant = _read_json(BattleScenario.resource_path(scenario, script_key))
	if not BattleScenarioRuleAdapter.script_payload_valid(scenario, script):
		return "missing_battle_script_payload"
	intake["script"] = script
	return ""


static func _load_scenario_rules(loop: Dictionary, scenario: Dictionary, _intake: Dictionary) -> String:
	var rules := BattleScenarioRuleAdapter.runtime_rules(scenario)
	loop["player_unit_id"] = str(scenario["player_unit_id"])
	loop["turn"] = 1
	loop["objective_phase"] = str(rules["initial_objective_phase"])
	loop["events"] = rules["events"]
	loop["reinforcement_templates"] = []
	for entry in rules["reinforcements"]:
		var template := BattlePlayLoop._unit(loop, str(entry["template_unit_id"])).duplicate(true)
		if template.is_empty():
			return "missing_reinforcement_template"
		loop["reinforcement_templates"].append(template)
	loop["reinforcement_spawn_cells"] = []
	for cell in rules["reinforcement_spawn_cells"]:
		loop["reinforcement_spawn_cells"].append(Vector2i(int(cell[0]), int(cell[1])))
	loop["escape_zone"] = rules["script_fallback"]["escape_zone"]
	loop["allow_optional_clear_after_switch"] = bool(rules["allow_optional_clear_after_switch"])
	return ""


static func _initialize_script_state(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	# The adapters return a fresh dictionary (and mark an unsupported adapter as a
	# scenario_error themselves); fold it back into the one loop the pipeline owns.
	var next := BattleScenarioRuleAdapter.initialize_script_state(loop, scenario, intake["script"])
	loop.clear()
	loop.merge(next)
	return ""


## No script_actor_templates but a winfail chain walks a standing unit: the empty template
## set lets the fired chain commit the walk (ScriptActorCreationRules.walk_only_source).
static func _load_script_walk_source(loop: Dictionary, _scenario: Dictionary, _intake: Dictionary) -> String:
	if loop.has("script_actor_source"):
		return ""
	var source := ScriptActorCreationRules.walk_only_source(loop.get("winfail_script_rules", {}))
	if not source.is_empty():
		loop["script_actor_source"] = source
		loop["script_actor_transactions"] = []
	return ""


static func _load_opening_timeline(_loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	intake["opening_events"] = []
	var timeline_path := BattleScenario.resource_path(scenario, "opening_timeline")
	if timeline_path == "":
		return ""
	var timeline: Variant = JSON.parse_string(FileAccess.get_file_as_string(timeline_path))
	if not timeline is Dictionary or not timeline.get("events") is Array:
		return "invalid_wait_opening_source"
	intake["opening_events"] = timeline["events"]
	return ""


## The opening's committed effects on the field that a battle entered without playing it
## (dev first control, a restored checkpoint) must still show — loop state
## `opening_story_state`, saved with the battle:
## - STORY actSetRandomPos (0x451d0f): the slot table is shuffled once per battle — for i in
##   0..n-1, when the roll is odd, slot i swaps with slot i+2 (minus 5 past the end); the
##   insert that names slot k then lands on the shuffled table entry (STORY037's gems and
##   guardians, bound by insert order `<symbol>/insertN`, move with their slot).
##   each roll is one raw 0x458c10 draw & 1 on the loop's global stream (`global_rng`),
##   before the opening's births draw theirs.
## - the stand objects its actDeletePosObject／actDeleteRandomPosObject remove (the 37 statues
##   under the guardians, 59's statue under 地劫神, 77's), as anchors for
##   BattleSceneRuntime.apply_opening_object_deletes. A delete a later actInsertStoryObject
##   replaces at the same anchor (STORY010's burnt tree) is left out: the replacement story
##   object is not re-created without the opening either.
static func _load_opening_story_state(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	var events: Array = intake["opening_events"]
	var table: Array[Vector2i] = []
	var order: Array = []
	var rolls: Array = []
	var deletes: Array = []
	var inserts := {}
	for event in events:
		var args: Array = (event as Dictionary).get("args", [])
		match str(event.get("kind", "")):
			"random_position_set":
				table.clear()
				for index in range(mini(int(str(args[0])) if not args.is_empty() else 0, 5)):
					if args.size() > 2 + index * 2:
						table.append(Vector2i(int(str(args[1 + index * 2])), int(str(args[2 + index * 2]))))
				order = range(table.size())
				rolls = []
				for index in range(table.size()):
					var roll := GlobalRandomStream.loop_draw(loop, -1) & 1
					rolls.append(roll)
					var other := index + 2 if index + 2 < 5 else index + 2 - 5
					if roll == 1 and other < table.size():
						var held: int = order[index]
						order[index] = order[other]
						order[other] = held
			"random_position_object_delete":
				var slot := int(str(args[0])) if not args.is_empty() else -1
				if slot >= 0 and slot < order.size():
					var anchor: Vector2i = table[order[slot]]
					deletes.append({"x": anchor.x, "y": anchor.y, "range": int(str(args[1])) if args.size() > 1 else 0, "proc_code": str(args[2]) if args.size() > 2 else "", "source_event_id": str(event.get("id", ""))})
			"position_object_delete":
				if args.size() >= 2:
					deletes.append({"x": int(str(args[0])), "y": int(str(args[1])), "range": int(str(args[2])) if args.size() > 2 else 0, "proc_code": str(args[3]) if args.size() > 3 else "", "source_event_id": str(event.get("id", ""))})
			"story_object_insert":
				if args.size() >= 3:
					var at := Vector2i(int(str(args[1])), int(str(args[2])))
					deletes = deletes.filter(func(row): return Vector2i(int(row["x"]), int(row["y"])) != at)
			"object_insert_random_position":
				var symbol := str(args[0]) if not args.is_empty() else ""
				inserts[symbol] = int(inserts.get(symbol, 0)) + 1
				var slot := int(str(args[3])) if args.size() > 3 else -1
				var binding: Dictionary = scenario.get("opening", {}).get("actor_bindings", {}).get("%s/insert%d" % [symbol, inserts[symbol]], {})
				var unit := BattlePlayLoop._unit(loop, str(binding.get("unit_id", "")))
				if unit.is_empty() or slot < 0 or slot >= order.size():
					continue
				var pixel: Vector2i = table[order[slot]] + Vector2i(int(str(args[1])), int(str(args[2])))
				var cell := Vector2i(floori(pixel.x / 32.0), floori(pixel.y / 32.0))
				if unit.get("ai_home_coord") == unit["coord"]:
					unit["ai_home_coord"] = cell
				unit["coord"] = cell
	loop["opening_story_state"] = {"policy": "opening_story_state_v1", "random_slot_table": table, "random_slot_order": order, "random_slot_rolls": rolls, "object_deletes": deletes}
	return ""


static func _load_script_waits(loop: Dictionary, scenario: Dictionary, intake: Dictionary) -> String:
	var wait_source := ScriptWait.initial_source(scenario, loop["units"], intake["opening_events"])
	if not wait_source["ok"]:
		return str(wait_source["reason"])
	loop["script_wait_source"] = wait_source["source"]
	for assignment in wait_source["source"]["initial"]:
		BattlePlayLoop._unit(loop, assignment["unit_id"])["ai_wait_remaining"] = assignment["rounds"]
	return ""


static func initialize_roster_growth(loop: Dictionary) -> Dictionary:
	if not bool(loop.get("scenario_ok", false)):
		return BattlePlayLoop.copy(loop)
	var proposal := InitialRosterGrowthRules.prepare(loop)
	if not proposal["ok"]:
		var failed := BattlePlayLoop.copy(loop)
		failed.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": proposal.get("reason", "invalid_initial_roster")}, true)
		return failed
	var next: Dictionary = proposal["loop"]
	if not loop.has("initial_roster_growth"): next["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop._queue_actors(next))
	return next


## Campaign hand-off seam: the controlled party carried from the previous battle
## enters the freshly created loop through the shared progression refresh, before
## begin_battle. Empty carry or an invalid scenario leaves the loop untouched.
static func apply_campaign_carry(loop: Dictionary, carry: Dictionary) -> Dictionary:
	if carry.is_empty() or not bool(loop.get("scenario_ok", false)) or str(loop.get("interaction", "")) != "idle":
		return BattlePlayLoop.copy(loop)
	var applied := CampaignCarryRules.apply(loop, carry)
	# The carry is JSON from a previous battle or save; the merged roster must still
	# match the shared unit contract before begin_battle.
	var roster_error := UnitSchema.roster_error(applied.get("units", []))
	if roster_error != "":
		applied.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": "unit_schema:" + roster_error}, true)
	return applied
