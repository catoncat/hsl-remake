extends RefCounted
## Dispatch seam between the shared PlayLoop and battle-specific script rules.
## winfail runs the data-driven interpreter over the seed's winfail script for
## every seed-backed battle (the first battle level 51 included); development
## battles read authored objectives. The hand-written level modules (51, 52, 53)
## were retired once the interpreter matched them; their ids fail explicitly.
## provenance:
##   rules: remake-invented (dispatch seam: winfail interpreter vs development objectives)

const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const DevelopmentBattleRules = preload("res://game/sim/DevelopmentBattleRules.gd")

const WINFAIL := "winfail"
const DEVELOPMENT := "development_battle"
## Dialogue namespace of the deciding status' terminal messages (WinfailScenarioRules).
const TERMINAL_DIALOGUE_KEY := WinfailScenarioRules.TERMINAL_DIALOGUE_KEY


static func adapter_id(scenario: Dictionary) -> String:
	return str(scenario.get("rule_adapter", ""))


static func runtime_rules(scenario: Dictionary) -> Dictionary:
	match adapter_id(scenario):
		WINFAIL, DEVELOPMENT:
			return (scenario.get("scenario_rules", {}) as Dictionary).duplicate(true)
		_:
			return {}


static func script_resource_key(scenario: Dictionary) -> String:
	match adapter_id(scenario):
		WINFAIL:
			return "battle_seed"
		DEVELOPMENT:
			return "development_objectives"
		_:
			return ""


static func script_payload_valid(scenario: Dictionary, payload: Variant) -> bool:
	if typeof(payload) != TYPE_DICTIONARY:
		return false
	match adapter_id(scenario):
		WINFAIL:
			return WinfailScenarioRules.seed_has_winfail(payload as Dictionary)
		DEVELOPMENT:
			return (payload as Dictionary).get("schema") == "hsl_development_objectives.v1"
		_:
			return false


static func initialize_script_state(loop: Dictionary, scenario: Dictionary, script_or_seed: Dictionary) -> Dictionary:
	match str(loop.get("rule_adapter", adapter_id(scenario))):
		WINFAIL:
			return WinfailScenarioRules.initialize_script_state(loop, scenario, script_or_seed)
		DEVELOPMENT:
			return DevelopmentBattleRules.initialize(loop, scenario, script_or_seed)
		_:
			var failed := BattleLoopConfig.copy(loop)
			failed["scenario_ok"] = false
			failed["interaction"] = "scenario_error"
			failed["scenario_error"] = "unsupported_rule_adapter"
			return failed


static func run_event_hooks(loop: Dictionary, attacked: bool = false) -> Dictionary:
	## One completed-action scan; `attacked`: the finishing actor attacked in this action,
	## the only scan in which attack-context conditions (actCheckPlayerAttacked) hold.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.run_event_hooks(loop, attacked)
		_:
			return BattleLoopConfig.copy(loop)


static func reinforcement_deficits(loop: Dictionary) -> Dictionary:
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.reinforcement_deficits(loop)
		_:
			return {}


static func story_dialogue_messages(loop: Dictionary) -> Array[Dictionary]:
	## Scenario-owned story/result dialogue as {key, speaker_id, message_id}; only
	## script rules that carry resource message ids report through this seam.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.story_dialogue_messages(loop)
		_:
			var none: Array[Dictionary] = []
			return none


static func objective_board(loop: Dictionary) -> Dictionary:
	## Win Board labels as {"win": [{speaker_id, message_id, actor_token}], "fail": [...],
	## "event": [...]} (resource ids only); development battles report an empty board.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.objective_board(loop)
		_:
			return {"win": [], "fail": [], "event": []}


static func result_message_id(loop: Dictionary, outcome: Dictionary) -> String:
	## winfail `message = SID,ID` label for a terminal outcome, or "" when the
	## scenario rules do not carry one.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.result_message_id(loop, outcome)
		_:
			return ""


static func commit_outcome(loop: Dictionary) -> Dictionary:
	## Called by the PlayLoop right before it freezes a decided outcome: rules that
	## keep a fired-status record apply the deciding status' result chain once
	## (WinfailScenarioRules.commit_outcome); the others return the loop unchanged.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.commit_outcome(loop)
		_:
			return BattleLoopConfig.copy(loop)


static func victory_state(loop: Dictionary, escape_zone: Array = []) -> Dictionary:
	## The decided BattleOutcome ({result, reason}), `{}` while the battle is ongoing.
	match str(loop.get("rule_adapter", "")):
		WINFAIL:
			return WinfailScenarioRules.victory_state(loop, escape_zone)
		DEVELOPMENT:
			return DevelopmentBattleRules.victory(loop)
		_:
			return {}
