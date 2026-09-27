extends RefCounted
## Versioned, checksummed single-battle saves at quiet/loot boundaries.
## Variant decoding never allows objects. No initialization, RNG or settlement
## is replayed on load; the restored dictionary replaces the sole PlayLoop, so the
## saved damage stream continues exactly where it stopped. The global stream is not
## saved: the restored loop keeps the running battle's live words, so the AI's choices
## after a load may differ from the ones before the save.
## provenance:
##   rules: remake-invented (versioned checksummed single-battle save format; the original has no in-battle save)
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
const BattlePlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const MAGIC := "HSL-BATTLE-1\n"
const MAX_BYTES := 16 * 1024 * 1024
## v6: the NPC birth receipts (entry_growth／entry_readjust, initial_roster_growth, script
## creation) record global-stream words instead of v5's Park-Miller `initialization_rng`
## integers, and the global stream `global_rng` is left out of the save (the running
## battle's live words join the restored loop, as current's configuration does). A v5 save
## is refused by name: its integer birth receipts cannot be re-proved on the global
## generator, and no migration exists.
## v5: the one damage stream `damage_rng` (DamageRandomStream, two u32 words) replaces
## v4's separate Park-Miller `item_rng`／`recovery_rng`, and the item／turn-end receipts
## record its words. A v4 save is refused by name: its integer receipts cannot be
## re-proved on the new stream and a fresh stream would break the same-results-after-
## load promise. `battle_outcome` (and winfail_runtime.resolved.outcome) is the
## BattleOutcome structure {result, reason}, `{}` while undecided; the terminal dialogue
## key is WinfailScenarioRules.TERMINAL_DIALOGUE_KEY. v3 wrote the outcome as a key
## string ("victory_escape" …) and is refused by name like v1 (first-battle skill
## manifests in the digest) and v2 (whole loop written): no save migration exists. The snapshot
## carries the state half of the loop only — every key outside BattlePlayLoop.CONFIG_SHARED. The
## read-only configuration (terrain, skill book, catalogs, script sources …) is the
## running battle's own, matched by the configuration digest and shared back into the
## restored loop by reference (docs/architecture/BATTLE_CONFIG_STATE.md).
const SCHEMA := "hsl_battle_checkpoint.v6"
const RETIRED_SCHEMAS := ["hsl_battle_checkpoint.v1", "hsl_battle_checkpoint.v2", "hsl_battle_checkpoint.v3", "hsl_battle_checkpoint.v4", "hsl_battle_checkpoint.v5"]
const CONFIG_KEYS := BattlePlayLoop.CONFIG_KEYS


static func digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()


static func configuration(loop: Dictionary) -> String:
	var fields: Array = []
	for key in CONFIG_KEYS:
		if not loop.has(key): return ""
		fields.append(loop[key])
	if loop.get("script_wait_source", {}).get("policy") != BattlePlayLoop.ScriptWait.POLICY: return ""
	fields.append(loop["script_wait_source"])
	if loop.get("entry_growth_data",{}).get("schema") != "hsl_entry_growth_sources.v1": return ""
	fields.append(loop["entry_growth_data"])
	if loop.has("script_actor_source"):
		if loop["script_actor_source"].get("policy") != BattlePlayLoop.ScriptActors.POLICY: return ""
		fields.append(loop["script_actor_source"])
	if loop.has("treasure_source"):
		if BattlePlayLoop.Treasure.source_error(loop[LoopKeys.TREASURE_SOURCE], loop["equipment_items"], loop[LoopKeys.MAP_SIZE]) != "": return ""
		fields.append(loop[LoopKeys.TREASURE_SOURCE])
	if loop.get("rule_adapter") == "winfail":
		var source: Variant = loop.get("script_presentation_source")
		if not source is Dictionary or source.get("policy") != "script_cursor_v1" or not source.get("playable_keys") is Array or not source.get("digest") is String or source["digest"].length() != 64: return ""
		fields.append(loop.get("winfail_script_rules"))
		fields.append(source)
	return digest(var_to_bytes(fields))


## The saved half of the loop: every key outside the shared configuration, except the
## global stream (the original keeps 0x4795d4／0x4795d8 out of its save).
static func state(loop: Dictionary) -> Dictionary:
	var out := {}
	for key in loop:
		if not BattlePlayLoop.CONFIG_SHARED.has(key) and key != GlobalRandomStream.LOOP_KEY:
			out[key] = loop[key]
	return out


## A saved state joined with the running battle's configuration blocks (shared by
## reference, like every loop the battle copies) and its live global stream words.
## Configuration keys in `saved` are ignored: the digest already proved the running
## battle's blocks are the saved ones.
static func restored(saved: Dictionary, current: Dictionary) -> Dictionary:
	var loop := {}
	for key in BattlePlayLoop.CONFIG_SHARED:
		if current.has(key):
			loop[key] = current[key]
	for key in saved:
		if not BattlePlayLoop.CONFIG_SHARED.has(key) and key != GlobalRandomStream.LOOP_KEY:
			loop[key] = saved[key]
	if GlobalRandomStream.valid(current.get(GlobalRandomStream.LOOP_KEY)):
		loop[GlobalRandomStream.LOOP_KEY] = (current[GlobalRandomStream.LOOP_KEY] as Array).duplicate()
	return loop


static func plain(value: Variant, depth: int = 0) -> bool:
	if depth > 40: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_VECTOR2I: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2: return value.is_finite()
		TYPE_ARRAY:
			for child in value:
				if not plain(child, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) not in [TYPE_STRING, TYPE_INT, TYPE_VECTOR2I] or not plain(value[key], depth + 1): return false
			return true
	return false


## `current` is the running battle's loop: its configuration digest must match the
## snapshot's and its configuration blocks complete the saved state for the checks below.
static func validate(snapshot: Variant, current: Dictionary) -> String:
	if snapshot is Dictionary and RETIRED_SCHEMAS.has(snapshot.get("schema")): return "unsupported_save_schema"
	if not snapshot is Dictionary or snapshot.get("schema") != SCHEMA or not plain(snapshot): return "invalid_save_format"
	if not snapshot.get("loop") is Dictionary or not snapshot.get("view") is Dictionary: return "missing_save_state"
	var saved: Dictionary = snapshot["loop"]
	var view: Dictionary = snapshot["view"]
	var expected := configuration(current)
	if expected == "" or snapshot.get("configuration") != expected: return "incompatible_save_configuration"
	var loop := restored(saved, current)
	if loop.get("schema") != "hsl_first_scene_play_loop.v1" or loop.get("scenario_ok") != true: return "invalid_saved_battle"
	for key in ["turn_queue", "command_menu", "give_session", "settlement"]:
		if not loop.get(key) is Dictionary: return "missing_saved_dictionary"
	for key in ["units", "rewarded_unit_ids", "event_log", "reinforcement_templates", LoopKeys.KNOWN_UNIT_IDS]:
		if not loop.get(key) is Array: return "missing_saved_array"
	if loop[LoopKeys.UNITS].is_empty() or loop[LoopKeys.UNITS].size() > 4096 or not loop[LoopKeys.GIVE_SESSION].is_empty(): return "unsupported_saved_roster"
	# Before the placement checks: they read the map through the saved edits.
	var terrain_error := BattlePlayLoop.TerrainEdits.state_error(loop)
	if terrain_error != "": return terrain_error
	if loop.get(LoopKeys.INTERACTION) not in [Interaction.ACTION_MENU, Interaction.AI_RESOLVING, Interaction.BATTLE_RESULT]: return "unsupported_save_boundary"
	for key in ["turn", "item_revision"]:
		if not BattlePlayLoop.RewardRules.integer(loop.get(key)): return "invalid_saved_counter"
	if not DamageRandomStream.valid(loop.get(DamageRandomStream.LOOP_KEY)): return "invalid_saved_damage_rng"
	if not GlobalRandomStream.valid(loop.get(GlobalRandomStream.LOOP_KEY)): return "missing_live_global_rng"
	for key in ["pending_move", "moved_this_action", "attacked_this_action"]:
		if not loop.get(key) is bool: return "invalid_saved_action"
	if not loop.get("action_attacker_id", "") is String: return "invalid_saved_action"
	if not loop.get(LoopKeys.PENDING_MOVE_FROM) is Vector2i or not loop.get(LoopKeys.SELECTED_UNIT_ID) is String: return "invalid_saved_action"
	if BattleOutcome.error(loop.get(LoopKeys.BATTLE_OUTCOME)) != "": return "invalid_saved_outcome"
	var ids: Array = []
	for actor in loop[LoopKeys.UNITS]:
		if not actor is Dictionary or not actor.get("id") is String or actor["id"] == "" or ids.has(actor["id"]): return "invalid_saved_identity"
		ids.append(actor["id"])
		if not actor.get("coord") is Vector2i or not actor.get("combat_profile") is Dictionary or not actor.get("defeated") is bool: return "invalid_saved_actor"
		for key in ["hp", "max_hp", "level", "exp", "pending_stat_points", "live_speed", "move_point"]:
			if not BattlePlayLoop.RewardRules.integer(actor.get(key)): return "invalid_saved_vitals"
		if actor["hp"] > actor["max_hp"] or actor["defeated"] != (actor["hp"] == 0) or BattlePlayLoop.StatusEffectRules.input_error(actor) != "": return "inconsistent_saved_vitals"
		if BattlePlayLoop.TraversalRules.actor_error(actor, loop[LoopKeys.SKILL_BOOK]) != "": return "invalid_saved_actor_traversal"
		if BattlePlayLoop.ExperienceRules.actor_error(actor) != "" or not BattlePlayLoop.ExperienceRules.multiplier(actor, loop["equipment_items"])["ok"]: return "invalid_saved_experience"
		if BattlePlayLoop.CoreCombatRules.input_error(actor) != "": return "invalid_saved_physical_profile"
		if not BattlePlayLoop.attack_count(loop, actor)["ok"]: return "invalid_saved_extra_attack_source"
		if not BattlePlayLoop.weapon_pattern(loop, actor)["ok"]: return "invalid_saved_weapon_range"
		if not BattlePlayLoop.ExtraActionRules.equipment(actor, loop["equipment_items"])["ok"]: return "invalid_saved_extra_action_source"
		if BattlePlayLoop._resource_input_error(loop, actor) != "": return "invalid_saved_resource_state"
		var placement := BattlePlayLoop.TraversalRules.placement_error(actor, loop[LoopKeys.UNITS], BattlePlayLoop.TerrainEdits.tiles(loop), loop[LoopKeys.MAP_SIZE], true)
		if placement != "": return placement
		var mobility_error := BattlePlayLoop.MobilityRules.saved_error(actor, loop["equipment_items"])
		if mobility_error != "": return mobility_error
		var ai_profile: Dictionary = loop["ai_profiles"]["actors"].get(str(actor.get("actor_id", "")), {}).get("profile", {})
		if BattlePlayLoop.AINavigationRules.state_error(actor, int(BattlePlayLoop.AINavigationRules.instance_profile(actor, ai_profile).get("ai_fixed", 0))) != "": return "invalid_saved_ai_navigation"
		if actor.has("growth_profile") and BattlePlayLoop.ProgressionRules.refresh_input_error(actor, loop["equipment_items"]) != "": return "invalid_saved_growth"
		var learning_error := BattlePlayLoop.ProgressionRules.Learning.input_error(actor, loop[LoopKeys.SKILL_BOOK].get("learning", {}))
		if learning_error != "": return learning_error
	var reward_error := BattlePlayLoop._reward_input_error(loop)
	for receipt in [loop.get(LoopKeys.LAST_ATTACK, {}), loop.get(LoopKeys.LAST_COMBAT, {})]:
		var sequence_error := BattlePlayLoop.SkillResolutionRules.RepeatedSpecialRules.receipt_error(receipt)
		if sequence_error != "": return sequence_error
		var stat_error := BattlePlayLoop.SkillResolutionRules.StatMagic.receipt_error(receipt,loop[LoopKeys.SKILL_BOOK])
		if stat_error != "": return stat_error
	if not ids.has(loop.get("player_unit_id")): return "invalid_saved_primary_actor"
	for known_id in loop[LoopKeys.KNOWN_UNIT_IDS]:
		if not known_id is String or not ids.has(known_id) or loop[LoopKeys.KNOWN_UNIT_IDS].count(known_id) != 1: return "invalid_saved_known_units"
	if reward_error != "": return reward_error
	var queue: Dictionary = loop["turn_queue"]
	if not queue.get("slots") is Array or not BattlePlayLoop.RewardRules.integer(queue.get("index"), 0, queue["slots"].size()) or not BattlePlayLoop.RewardRules.integer(queue.get("round")): return "invalid_saved_queue"
	if BattlePlayLoop.CoreTurnQueue.cancellation_input_error(queue) != "": return "invalid_saved_queue_eligibility"
	var presence_error := BattlePlayLoop.Presence.state_error(loop)
	if presence_error != "": return presence_error
	var wait_error := BattlePlayLoop.ScriptWait.state_error(loop)
	if wait_error != "": return wait_error
	var initialization_error := BattlePlayLoop.ReinforcementGrowth.state_error(loop)
	if initialization_error != "": return initialization_error
	var initial_error := BattlePlayLoop.InitialRosterGrowth.state_error(loop)
	if initial_error != "": return initial_error
	var script_actor_error := BattlePlayLoop.ScriptActors.state_error(loop)
	if script_actor_error != "": return script_actor_error
	var queued_ids: Array = []
	for slot in queue["slots"]:
		if not slot is Dictionary or not ids.has(slot.get("id")): return "invalid_saved_queue_actor"
		if queued_ids.has(slot["id"]): return "duplicate_saved_queue_actor"
		queued_ids.append(slot["id"])
	if loop[LoopKeys.INTERACTION] == Interaction.ACTION_MENU and (not ids.has(loop[LoopKeys.SELECTED_UNIT_ID]) or BattlePlayLoop.CoreTurnQueue.current(queue).get("id") != loop[LoopKeys.SELECTED_UNIT_ID]): return "invalid_saved_current_actor"
	if loop[LoopKeys.INTERACTION] == Interaction.ACTION_MENU and BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(loop, loop[LoopKeys.SELECTED_UNIT_ID])): return "invalid_saved_paralysis_phase"
	var settled: Dictionary = loop[LoopKeys.SETTLEMENT]
	if not settled.is_empty():
		if not BattlePlayLoop.RewardRules.integer(settled.get("sequence"), 1) or not BattlePlayLoop.RewardRules.integer(settled.get("revision")) or not settled.get("closed") is bool: return "invalid_saved_settlement"
		var settlement_error := BattlePlayLoop.Treasure.settlement_error(loop)
		if settlement_error != "": return settlement_error
		for key in ["pending", "claimed", "abandoned", "kills"]:
			if not settled.get(key) is Array: return "invalid_saved_loot"
		var entries: Array = []
		for item in settled["pending"]:
			if not item is Dictionary or not item.get("id") is String or entries.has(item["id"]) or not BattlePlayLoop.RewardRules.integer(item.get("code"), 1) or not loop["equipment_items"].has(str(item["code"])): return "invalid_saved_loot_entry"
			entries.append(item["id"])
	var rewarded: Array = []
	for id in loop["rewarded_unit_ids"]:
		if not ids.has(id) or rewarded.has(id) or not BattlePlayLoop.unit(loop, id)["defeated"]: return "invalid_saved_death_ledger"
		rewarded.append(id)
	if not view.get("camera") is Vector2 or not view.get("shown_story_events") is Array: return "invalid_saved_presentation"
	if view.has("growth_offered_levels"):
		if not view["growth_offered_levels"] is Dictionary: return "invalid_saved_presentation"
		for id in view["growth_offered_levels"]:
			if not ids.has(id) or not BattlePlayLoop.RewardRules.integer(view["growth_offered_levels"][id], 1): return "invalid_saved_presentation"
	elif not BattlePlayLoop.RewardRules.integer(view.get("growth_notified_level"), 1): return "invalid_saved_presentation"
	if view.get("treasure_presented_sequence", 0) != loop.get(LoopKeys.TREASURES, {}).get("receipts", []).size(): return "pending_saved_treasure_presentation"
	var fired: Array = loop.get(LoopKeys.WINFAIL_RUNTIME, {}).get("fired", [])
	if not BattlePlayLoop.RewardRules.integer(view.get("script_cutscene_consumed", 0), 0, fired.size()): return "invalid_saved_script_cursor"
	var playable: Array = loop.get("script_presentation_source", {}).get("playable_keys", [])
	for index in range(fired.size()):
		if not fired[index] is Dictionary or not fired[index].get("key") is String: return "invalid_saved_script_firing"
		if playable.has(fired[index]["key"]) and index >= int(view.get("script_cutscene_consumed", 0)):
			return "pending_saved_script_cutscene"
	for event in view["shown_story_events"]:
		if not event is String: return "invalid_saved_story_cursor"
	return ""


## The restored per-member growth offers. A save from before `growth_offered_levels` held
## one battle-wide `growth_notified_level`; it restores every member as offered at its
## current level. A member still holding points (a save from when the window could be
## postponed) is left unoffered either way, so its window opens at the first quiet moment —
## the original's window closes only with every point placed (original_growth_window.md §4).
static func growth_offered_levels(view: Dictionary, loop: Dictionary) -> Dictionary:
	var offered := {}
	if view.has("growth_offered_levels"): offered = (view["growth_offered_levels"] as Dictionary).duplicate()
	else:
		for unit in loop.get(LoopKeys.UNITS, []):
			offered[str(unit["id"])] = int(unit.get("level", 1))
	for unit in loop.get(LoopKeys.UNITS, []):
		if int(unit.get("pending_stat_points", 0)) > 0: offered.erase(str(unit["id"]))
	return offered


static func encode(loop: Dictionary, view: Dictionary) -> Dictionary:
	var snapshot := {"schema": SCHEMA, "configuration": configuration(loop), "loop": state(loop), "view": view}
	var error := validate(snapshot, loop)
	if error != "": return {"ok": false, "reason": error}
	var payload := var_to_bytes(snapshot)
	if payload.size() > MAX_BYTES - 128: return {"ok": false, "reason": "save_too_large"}
	var bytes := (MAGIC + digest(payload) + "\n").to_utf8_buffer()
	bytes.append_array(payload)
	return {"ok": true, "bytes": bytes}


## Returns {ok, snapshot} with `snapshot.loop` already joined to `current`'s configuration.
static func decode(bytes: PackedByteArray, current: Dictionary) -> Dictionary:
	var start := MAGIC.length() + 65
	if bytes.size() < start + 4 or bytes.size() > MAX_BYTES or bytes.slice(0, MAGIC.length()) != MAGIC.to_utf8_buffer(): return {"ok": false, "reason": "invalid_save_header"}
	var payload := bytes.slice(start)
	if bytes[MAGIC.length() + 64] != 10 or digest(payload) != bytes.slice(MAGIC.length(), start - 1).get_string_from_ascii(): return {"ok": false, "reason": "save_checksum_mismatch"}
	if (payload.decode_u32(0) & 0xffff) != TYPE_DICTIONARY: return {"ok": false, "reason": "invalid_save_payload"}
	var snapshot: Variant = bytes_to_var(payload) # Objects are never instantiated.
	var error := validate(snapshot, current)
	if error != "": return {"ok": false, "reason": error}
	snapshot["loop"] = restored(snapshot["loop"], current)
	return {"ok": true, "snapshot": snapshot}


static func write(path: String, loop: Dictionary, view: Dictionary) -> Dictionary:
	var encoded := encode(loop, view)
	if not encoded["ok"]: return encoded
	var target := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK: return {"ok": false, "reason": "save_directory_failed"}
	var temporary := target + ".tmp-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return {"ok": false, "reason": "save_open_failed"}
	file.store_buffer(encoded["bytes"])
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "reason": "save_replace_failed"}
	return {"ok": true}


static func read(path: String, current: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "reason": "save_not_found"}
	if file.get_length() > MAX_BYTES: return {"ok": false, "reason": "save_too_large"}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return decode(bytes, current)
