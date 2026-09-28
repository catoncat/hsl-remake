extends RefCounted
## Conditional party installs for random encounters (content/battles/battle_5NN.json,
## tools/hsltools/levels/battle.py build_encounter): every encounter EVEF installs the nine
## registered slots as 有才產生, so a scenario lists each fieldable slot as a
## player_controlled unit flagged install_if_carried and the remake fields only the members
## the campaign carry holds (matched by actor_id — the same member keeps one actor id across
## scenarios while its unit id may differ). Static-derived basis: the original
## defProcPlayerInstall (0x4080b0) reads obj_Data8 = 1 as a conditional install and lets only
## an existing, enabled registered slot reach the constructor — an empty or disabled slot
## takes the placeholder-deletion path (docs/evidence_packets/static_reverse/
## original_player_install.md, OBJ-012 codes 180–188). The carry stands in for the
## original's registered-and-enabled slot table. A registered-but-disabled slot is
## unreachable in the original: 0x42caa0 tests 0x80000000, but the only table writer
## 0x42c700 is called from 0x42c869 (new game, 800), 0x42cb47 (800+slot) and 0x43493d
## (job-up object code), 0x42cb50 keeps the low 16 bits and 0x42cafa only clears, so no
## path sets the disable bit (static-derived). A scenario launched without a campaign hand-off fields every slot so dev /
## test launches show the whole roster.
##
## Slots the scenario cannot field yet (conditional_party.unavailable_slots: no reviewed
## template or shared portrait) are an explicit failure, not a silent drop: blocked_members()
## names the carried members the encounter would have to leave out, and the world map keeps
## the party on the map with a card instead of entering.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_install.md
##   rules: remake-invented (carry stands in for the registered-and-enabled slot table; dev launches field every slot)

const SCHEMA := "hsl_conditional_party.v1"


static func has_conditional_party(scenario: Dictionary) -> bool:
	return typeof(scenario.get("conditional_party")) == TYPE_DICTIONARY


## Carried player members by actor id -> carry unit id (CampaignCarryRules.capture units).
static func carried_actor_ids(carry: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var units: Dictionary = carry.get("units", {}) if typeof(carry.get("units")) == TYPE_DICTIONARY else {}
	for unit_id in units:
		var record: Variant = units[unit_id]
		if typeof(record) == TYPE_DICTIONARY:
			result[str((record as Dictionary).get("actor_id", ""))] = str(unit_id)
	return result


## The scenario with its install_if_carried units filtered by the carry. Returns
## {scenario, receipt}; receipt = {schema, mode, installed, skipped}.
static func apply(scenario: Dictionary, carry: Dictionary) -> Dictionary:
	var receipt := {"schema": SCHEMA, "mode": "not_conditional", "installed": [], "skipped": []}
	if not has_conditional_party(scenario):
		return {"scenario": scenario, "receipt": receipt}
	if carry.is_empty():
		receipt["mode"] = "no_carry_all_slots"
		for unit_value in scenario.get("playable_units", []):
			if typeof(unit_value) == TYPE_DICTIONARY and bool((unit_value as Dictionary).get("install_if_carried", false)):
				receipt["installed"].append(str((unit_value as Dictionary).get("id", "")))
		return {"scenario": scenario, "receipt": receipt}
	receipt["mode"] = "install_if_carried"
	var carried := carried_actor_ids(carry)
	var next := scenario.duplicate(true)
	var units: Array = []
	for unit_value in scenario.get("playable_units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = (unit_value as Dictionary).duplicate(true)
		if not bool(unit.get("install_if_carried", false)):
			units.append(unit)
			continue
		var actor_id := str(unit.get("actor_id", ""))
		if carried.has(actor_id):
			receipt["installed"].append(str(unit.get("id", "")))
			units.append(unit)
		else:
			receipt["skipped"].append(str(unit.get("id", "")))
	next["playable_units"] = units
	return {"scenario": next, "receipt": receipt}


## Carried player members the scenario lists as unavailable slots (cannot be fielded yet):
## [{actor_id, unit_id, reason}], empty when the encounter can take the whole party.
static func blocked_members(scenario: Dictionary, carry: Dictionary) -> Array:
	var blocked: Array = []
	if not has_conditional_party(scenario) or carry.is_empty():
		return blocked
	var carried := carried_actor_ids(carry)
	for slot_value in (scenario["conditional_party"] as Dictionary).get("unavailable_slots", []):
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		var actor_id := str(slot.get("actor_id", ""))
		if carried.has(actor_id):
			blocked.append({"actor_id": actor_id, "unit_id": str(carried[actor_id]), "reason": str(slot.get("reason", ""))})
	return blocked
