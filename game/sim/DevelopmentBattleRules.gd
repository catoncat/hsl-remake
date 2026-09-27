extends RefCounted
## Authored training objectives, separate from source scenario scripts.
## Shared PlayLoop owns every actor, queue, resource and outcome mutation.
## provenance:
##   rules: remake-invented (authored training objectives for development trials)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const LoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
## The shared defeat outcome (WinfailScenarioRules.DEFEAT_OUTCOME): the controlled player fell.
const DEFEAT_OUTCOME := BattleOutcome.DEFEAT_FALLEN


static func training_book(scenario: Dictionary, source: Dictionary) -> Dictionary:
	# Explicitly authored, player-visible training grants, never campaign learning.
	# The resulting single immutable definition book is also checkpoint identity.
	var grants: Variant = scenario.get("training_skill_grants", {})
	if not grants is Dictionary: return {"ok": false, "reason": "invalid_training_skill_grants"}
	var book := source.duplicate(true)
	for actor_id in grants:
		if not actor_id is String or not book["actors"].has(actor_id) or not grants[actor_id] is Array:
			return {"ok": false, "reason": "invalid_training_skill_grants"}
		for id in grants[actor_id]:
			if not id is String or not book["skills"].has(id): return {"ok": false, "reason": "unknown_training_skill"}
			if not book["actors"][actor_id]["supported_initial_ids"].has(id):
				book["actors"][actor_id]["supported_initial_ids"].append(id)
	if not grants.is_empty(): book["training_grants"] = grants.duplicate(true)
	return {"ok": true, "book": book}


static func initialize(loop: Dictionary, scenario: Dictionary, rules: Dictionary) -> Dictionary:
	var next := LoopConfig.copy(loop)
	var player_id := str(scenario.get("player_unit_id", ""))
	if rules.get("schema") != "hsl_development_objectives.v1" or player_id == "" or not next["units"].any(func(a):return a["id"] == player_id):
		next.merge({"scenario_ok":false,"interaction":"scenario_error","scenario_error":"invalid_development_objectives"},true)
		return next
	next["escape_zone"] = []
	for coord in rules["escape_zone"]: next["escape_zone"].append(Vector2i(int(coord[0]),int(coord[1])))
	next["event_log"] = []
	next["script_flags"] = {}
	next["objective_phase"] = "escape"
	next["scenario_title"] = str(scenario["title"])
	next["script_current_round"] = 1
	return next


static func victory(loop: Dictionary) -> Dictionary:
	## The decided BattleOutcome, `{}` while ongoing: the controlled player down or
	## absent loses; no living enemy_ai clears; the player on the escape zone escapes.
	var found := false
	for actor in loop["units"]:
		if actor["id"] != loop["player_unit_id"]: continue
		found = true
		if actor["hp"] <= 0 or actor["defeated"]: return DEFEAT_OUTCOME.duplicate()
	if not found: return DEFEAT_OUTCOME.duplicate()
	if not loop["units"].any(func(a):return a["battle_actor_role"] == "enemy_ai" and a["hp"] > 0 and not a["defeated"]): return BattleOutcome.victory(BattleOutcome.REASON_ENEMIES_CLEARED)
	for actor in loop["units"]:
		if actor["id"] == loop["player_unit_id"] and loop["escape_zone"].has(actor["coord"]): return BattleOutcome.victory(BattleOutcome.REASON_ESCAPE)
	return {}
