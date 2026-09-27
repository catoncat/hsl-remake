extends RefCounted
## Cross-battle carry-over for the controlled party. Pure transformation of the
## PlayLoop dictionary: capture from a finished battle, apply to a freshly created
## one, refresh derived stats through the shared progression/mobility rules.
## provenance:
##   rules: remake-invented
##     (carry model replaces the original registered-slot table —
##     docs/evidence_packets/static_reverse/original_check_targets.md#R8)
##   rules: static-derived docs/evidence_packets/static_reverse/original_town_job_up.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: runtime-measured docs/evidence_packets/static_reverse/original_stamina.md
##     (carried ST 0 at 0x407632, kept after actKeepPlayerST)
##   rules: static-derived docs/evidence_packets/static_reverse/original_campaign_actors.md
##     (reserve records: 0x42caf0, 0x407ec0)

const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const JobUpRules = preload("res://game/sim/JobUpRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const Values = preload("res://game/sim/Values.gd")

## v1 carries may hold `damage_rng` (two u32 words, JSON numbers); older ones without it
## are still accepted and the next battle keeps its freshly seeded stream. Carries written
## before the global stream (2026-09) also hold `initialization_rng`, the retired
## Park-Miller birth stream: accepted and ignored — births now draw the global stream,
## which is never carried.
const SCHEMA := "hsl_campaign_carry.v1"
## Present (true) only when the finished level's script ran actKeepPlayerST; each unit record
## then holds its `stamina`. Without it (every older carry too) a carried member enters at 0.
const KEEP_STAMINA := "keep_stamina"
## Live records of members whose registration a script removed without clearing the record
## (level 53: WINFAIL053 win 0 `actDeletePlayerCode SID_PLAYER1, 0` -> 0x42caf0(1, 0) zeroes only
## the slot code; the record at live index 2 is zeroed only when the second argument is non-zero).
## They are not party members (no town, no conditional installs), but the next install of the
## same member -- a scenario unit or a script `registered_player` insert -- takes the record,
## as 0x407ec0 copies no template over a record whose working attributes are non-zero.
const RESERVE := "reserve_units"
const DEFAULT_POLICY := {
	"roles": ["player_controlled"],
	"unit_keys": ["level", "exp", "pending_stat_points", "equipment", "weapon_code", "inventory", "kill_count", "permanent_gains", "learned_skills", "job_up_flags", "job_up_target_actor_id", "job_up_history"],
	"attribute_keys": ["str", "dex", "mind", "con"],
	"loop_keys": ["gold"],
	"restore_vitals": true,
}


static func capture(loop: Dictionary, policy: Dictionary = DEFAULT_POLICY) -> Dictionary:
	var units: Dictionary = {}
	var keep := keeps_stamina(loop)
	for unit_value in loop.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if str(unit.get("battle_actor_role", "")) not in policy.get("roles", DEFAULT_POLICY["roles"]):
			continue
		var record: Dictionary = {"actor_id": str(unit.get("actor_id", "")), "attributes": {}}
		for key in policy.get("unit_keys", DEFAULT_POLICY["unit_keys"]):
			if unit.has(key):
				record[key] = _copy(unit[key])
		var profile: Dictionary = unit.get("combat_profile", {})
		for key in policy.get("attribute_keys", DEFAULT_POLICY["attribute_keys"]):
			if profile.has(key):
				record["attributes"][key] = int(profile[key])
		if keep:
			record["stamina"] = int(unit.get("stamina", 0))
		units[str(unit.get("id", ""))] = record
	var loop_values: Dictionary = {}
	for key in policy.get("loop_keys", DEFAULT_POLICY["loop_keys"]):
		if loop.has(key):
			loop_values[key] = _copy(loop[key])
	var carry := {
		"schema": SCHEMA,
		"from_scenario_id": str(loop.get("scenario_id", loop.get("scenario_path", ""))),
		"from_outcome": BattleOutcome.of(loop),
		"units": units,
		"loop": loop_values,
		"restore_vitals": bool(policy.get("restore_vitals", true)),
		"claim_limit": "Remake campaign policy; original inter-level persistence is not proven.",
	}
	keep_damage_stream(carry, loop)
	var reserve := _reserve_forward(loop)
	if not reserve.is_empty(): carry[RESERVE] = reserve
	if keep:
		carry[KEEP_STAMINA] = true
	var pending := BattleRewardRules.carry_pending(loop)
	if not pending.is_empty(): carry["pending_rewards"] = pending
	return carry


## Reserve records this battle received and did not install go on unchanged.
static func _reserve_forward(loop: Dictionary) -> Dictionary:
	var reserve: Variant = loop.get("campaign_carry_receipt", {}).get(RESERVE, {})
	if not reserve is Dictionary: return {}
	var present := {}
	for unit in loop.get("units", []):
		if unit is Dictionary: present[str(unit.get("id", ""))] = true
	var forward := {}
	for unit_id in reserve:
		if not present.has(str(unit_id)): forward[str(unit_id)] = _copy(reserve[unit_id])
	return forward


## A separate party's battle (level 53, 緹娜 alone) hands the incoming party on unchanged
## (pass_level_entry) and leaves its own members behind as reserve records: the script removes
## their registration, not their live records (RESERVE).
static func separate_party_carry(incoming: Dictionary, loop: Dictionary) -> Dictionary:
	var carry := pass_level_entry(incoming, keeps_stamina(loop)) if not incoming.is_empty() else {}
	if carry.get("schema") != SCHEMA: carry = {"schema": SCHEMA, "units": {}, "loop": {}, "restore_vitals": true}
	keep_damage_stream(carry, loop)
	var reserve: Dictionary = (carry[RESERVE] as Dictionary).duplicate(true) if carry.get(RESERVE) is Dictionary else {}
	var own: Dictionary = capture(loop)["units"]
	for unit_id in own:
		if (carry.get("units", {}) as Dictionary).has(unit_id): continue
		var record: Dictionary = own[unit_id]
		record.erase("stamina")
		reserve[unit_id] = record
	if not reserve.is_empty(): carry[RESERVE] = reserve
	return carry


## A script of this battle ran actKeepPlayerST (opcode 69 sets [0x4c1af0]; WinfailActions
## records it as a keep_stamina carry request): the next level entry keeps the party's ST.
static func keeps_stamina(loop: Dictionary) -> bool:
	return (loop.get("winfail_runtime", {}).get("carry_requests", []) as Array).any(func(request): return request is Dictionary and request.get("kind") == "keep_stamina")


## A carry passed through a level entry that did not rebuild it (a story scene, a separate
## party's battle): 0x4075e0 consumes [0x4c1af0] there. `keep`: that level's script ran
## actKeepPlayerST again — the ST the party entered it with (0 unless it was kept) goes on.
static func pass_level_entry(carry: Dictionary, keep: bool) -> Dictionary:
	var next := carry.duplicate(true)
	var kept := bool(next.get(KEEP_STAMINA, false))
	next.erase(KEEP_STAMINA)
	if keep: next[KEEP_STAMINA] = true
	for record in (next.get("units", {}) as Dictionary).values():
		if not record is Dictionary: continue
		if not keep: record.erase("stamina")
		elif not kept: record["stamina"] = 0
	return next


## The damage stream belongs to the campaign, not to a party (one pair of words in the
## original save): a carry that passes a party through still takes the stream where this
## battle left it.
static func keep_damage_stream(carry: Dictionary, loop: Dictionary) -> void:
	if carry.get("schema") == SCHEMA and DamageRandomStream.valid(loop.get(DamageRandomStream.LOOP_KEY)):
		carry[DamageRandomStream.LOOP_KEY] = (loop[DamageRandomStream.LOOP_KEY] as Array).duplicate()


static func apply(loop: Dictionary, carry: Dictionary) -> Dictionary:
	var next := BattleLoopConfig.copy(loop)
	var receipt: Dictionary = {"schema": SCHEMA, "applied_unit_ids": [], "skipped_unit_ids": [], "loop_keys": [], "errors": []}
	if str(carry.get("schema", "")) != SCHEMA:
		receipt["errors"].append("invalid_carry_schema")
		next["campaign_carry_receipt"] = receipt
		return next
	var equipment_items: Dictionary = next.get("equipment_items", {})
	var pending: Variant = carry.get("pending_rewards", {})
	if not pending is Dictionary or (not pending.is_empty() and (pending.get("schema") != "hsl_pending_rewards.v1" or BattleRewardRules.pending_error(pending.get("items"), equipment_items) != "" or not next.get("settlement", {}).is_empty() or next.has("campaign_carry_receipt"))):
		receipt["errors"].append("invalid_carry_pending_rewards")
		next["campaign_carry_receipt"] = receipt
		return next
	if carry.has(DamageRandomStream.LOOP_KEY):
		var words := DamageRandomStream.from_words(carry[DamageRandomStream.LOOP_KEY])
		if words.is_empty():
			receipt["errors"].append("invalid_carry_damage_rng")
			next["campaign_carry_receipt"] = receipt
			return next
		next[DamageRandomStream.LOOP_KEY] = words
		receipt[DamageRandomStream.LOOP_KEY] = words.duplicate()
	var carried_units: Dictionary = carry.get("units", {})
	# A carried member was registered before: the construction copies no template (0x407ec0)
	# and the level entry clears its ST (0x407632) unless the previous script kept it.
	var kept := bool(carry.get(KEEP_STAMINA, false))
	var unfielded := {}
	for unit_id in carried_units:
		var value: Variant = carried_units[unit_id].get("stamina", 0) if kept and carried_units[unit_id] is Dictionary else 0
		unfielded[str(unit_id)] = Values.non_negative_int(value)
	var reserve: Dictionary = carry[RESERVE] if carry.get(RESERVE) is Dictionary else {}
	var reserve_left := {}
	for unit_id in reserve:
		if not carried_units.has(unit_id) and reserve[unit_id] is Dictionary: reserve_left[str(unit_id)] = _copy(reserve[unit_id])
	for unit_value in next.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		var unit_id := str(unit.get("id", ""))
		if reserve_left.has(unit_id):
			# A pre-placed install of a reserve member takes its record (ST 0, provisional).
			_apply_carried_unit(next, carry, unit, unit_id, reserve_left[unit_id], 0, equipment_items, receipt)
			reserve_left.erase(unit_id)
			continue
		if not carried_units.has(unit_id):
			continue
		var stamina: int = unfielded[unit_id]
		unfielded.erase(unit_id)
		var record: Dictionary = carried_units[unit_id]
		_apply_carried_unit(next, carry, unit, unit_id, record, stamina, equipment_items, receipt)
	for key in carry.get("loop", {}).keys():
		next[key] = _copy(carry["loop"][key])
		receipt["loop_keys"].append(key)
	if not receipt["applied_unit_ids"].is_empty():
		# Same initialization seam as create(): the queue reflects refreshed speeds.
		next["turn_queue"] = CoreTurnQueue.rebuild(CoreTurnQueue.queue_actors(next.get("units", []), func(unit): return not bool(unit.get("defeated", false))))
	receipt["from_scenario_id"] = str(carry.get("from_scenario_id", ""))
	# Carried members not in the opening roster: a later registered-player insert
	# (ScriptActorCreationRules) enters with this ST instead of the template's.
	for unit_id in unfielded.keys():
		if unfielded[unit_id] < 0 or unfielded[unit_id] > StaminaRules.CAP:
			unfielded.erase(unit_id)
			receipt["errors"].append("invalid_carry_stamina:" + unit_id)
	if not unfielded.is_empty(): receipt["unfielded_stamina"] = unfielded
	if not reserve_left.is_empty(): receipt[RESERVE] = reserve_left
	if not pending.is_empty():
		var retained: Array = pending["items"].duplicate(true)
		for item in retained:
			item["code"] = int(item["code"]); item["source_slot"] = int(item["source_slot"])
		receipt["pending_rewards"] = retained.duplicate(true)
		next["settlement"] = BattleRewardRules.settle({}, "campaign", 0, int(next["gold"]), 0, retained, [])
	next["campaign_carry_receipt"] = receipt
	return next


## One carried member onto its scenario unit: the job-up replay, carried keys and
## attributes, stamina, inventory and a growth refresh written into `unit`; a record that
## fails a check skips the unit with its error in `receipt`.
## A script `registered_player` insert of a reserve member: its record onto the new unit
## (ST 0, vitals full). Returns the first check error, or "".
static func apply_reserve_record(loop: Dictionary, unit: Dictionary, record: Dictionary) -> String:
	var receipt := {"applied_unit_ids": [], "skipped_unit_ids": [], "errors": []}
	_apply_carried_unit(loop, {"restore_vitals": true}, unit, str(unit.get("id", "")), record, 0, loop.get("equipment_items", {}), receipt)
	return "" if receipt["errors"].is_empty() else str(receipt["errors"][0])


static func _apply_carried_unit(next: Dictionary, carry: Dictionary, unit: Dictionary, unit_id: String, record: Dictionary, stamina: int, equipment_items: Dictionary, receipt: Dictionary) -> void:
	if str(record.get("actor_id", "")) != str(unit.get("actor_id", "")):
		receipt["skipped_unit_ids"].append(unit_id)
		receipt["errors"].append("actor_mismatch:" + unit_id)
		return
	var candidate := unit.duplicate(true)
	# A town job-up (命運神殿) lives in the carry as a history of merged target
	# templates; the scenario unit is the base template, so replay it first.
	var history: Array = record.get("job_up_history", []) if typeof(record.get("job_up_history")) == TYPE_ARRAY else []
	if not history.is_empty():
		var replayed := JobUpRules.replay_history(candidate, history)
		if not replayed["ok"]:
			receipt["skipped_unit_ids"].append(unit_id)
			receipt["errors"].append("job_up_replay_" + str(replayed["reason"]) + ":" + unit_id)
			return
		candidate = replayed["actor"]
		receipt["job_up_replayed_unit_ids"] = (receipt.get("job_up_replayed_unit_ids", []) as Array) + [unit_id]
	if stamina < 0 or stamina > StaminaRules.CAP:
		receipt["skipped_unit_ids"].append(unit_id)
		receipt["errors"].append("invalid_carry_stamina:" + unit_id)
		return
	candidate["stamina"] = stamina
	for key in record.keys():
		if key in ["actor_id", "attributes", "stamina"]:
			continue
		if not history.is_empty() and key in ["job_up_flags", "job_up_target_actor_id", "job_up_history"]:
			continue  # the replay already produced them from the live template
		candidate[key] = _copy(record[key])
	var profile: Dictionary = candidate.get("combat_profile", {}).duplicate(true)
	for key in record.get("attributes", {}).keys():
		profile[key] = int(record["attributes"][key])
	candidate["combat_profile"] = profile
	if candidate.has("inventory") and not InventoryRules.valid(candidate["inventory"]):
		receipt["skipped_unit_ids"].append(unit_id)
		receipt["errors"].append("invalid_inventory:" + unit_id)
		return
	# JSON stores integral item codes as floats. Validate before conversion,
	# then restore the same canonical runtime slots used by initialization.
	if candidate.has("inventory"): candidate["inventory"] = candidate["inventory"].map(func(value): return int(value))
	var error := ProgressionRules.refresh_input_error(candidate, equipment_items)
	if error == "": error = ProgressionRules.Learning.input_error(candidate, next.get("skill_book", {}).get("learning", {}))
	if error != "":
		receipt["skipped_unit_ids"].append(unit_id)
		receipt["errors"].append(error + ":" + unit_id)
		return
	var refreshed := ProgressionRules.refresh_growth_stats(candidate, equipment_items)
	if bool(carry.get("restore_vitals", true)):
		refreshed["hp"] = int(refreshed["max_hp"])
		refreshed["mp"] = int(refreshed["max_mp"])
	for key in refreshed.keys():
		unit[key] = refreshed[key]
	receipt["applied_unit_ids"].append(unit_id)


static func initialization_only(carry: Dictionary) -> Dictionary:
	# A separate party inherits the campaign's damage stream, never the other party's
	# actors, wallet or vitals (the global stream is the process's, not the carry's). Older
	# carries without the stream keep their baseline.
	if not carry.has(DamageRandomStream.LOOP_KEY): return {}
	return {"schema":carry.get("schema"),"units":{},"loop":{},"restore_vitals":false,
		"from_scenario_id":carry.get("from_scenario_id",""), DamageRandomStream.LOOP_KEY: _copy(carry[DamageRandomStream.LOOP_KEY])}


static func _copy(value: Variant) -> Variant:
	if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]:
		return value.duplicate(true)
	return value
