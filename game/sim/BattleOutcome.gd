extends RefCounted
## The decided result of a battle as one structure, spelled once:
## `{"result": VICTORY|DEFEAT, "reason": REASON_*}`; an undecided battle carries `{}`
## under LoopKeys.BATTLE_OUTCOME. Readers ask the predicates here (decided / won / lost /
## reason) instead of parsing a key; `describe` is the report-line spelling
## (`victory/escape`) and is never parsed back.
## provenance:
##   rules: remake-invented
##     (result／reason vocabulary of the remake's loop; a reason names the head condition of the deciding winfail status
##     (WinfailScenarioRules.outcome_for) or the dev-battle objective)

const VICTORY := "victory"
const DEFEAT := "defeat"

## Victory: the deciding win status' head condition.
const REASON_ESCAPE := "escape"  # actCheckPlayerArrivePos／actCheckAnyPlayerArrivePos, or the development escape zone
const REASON_ENEMIES_CLEARED := "enemies_cleared"  # actCheckEnemyTotalNumber, or no enemy_ai left in a development battle
const REASON_BOSS := "boss"  # actCheckPlayer／actCheckEnemy／actCheckPlayerHPLow／actCheckEnemyNumber
const REASON_SCRIPT := "script"  # any other head condition (actTRUE, flags, rounds …)
## Defeat: the controlled player fell (a winfail fail status, DevelopmentBattleRules) or the
## fielded party was wiped (WinfailScenarioRules.PARTY_WIPE_POLICY); one shared reason.
const REASON_FALLEN := "fallen"

const REASONS := {VICTORY: [REASON_ESCAPE, REASON_ENEMIES_CLEARED, REASON_BOSS, REASON_SCRIPT], DEFEAT: [REASON_FALLEN]}

## The five decided outcomes (read-only; producers hand out `duplicate()` copies).
const VICTORY_ESCAPE := {"result": VICTORY, "reason": REASON_ESCAPE}
const VICTORY_ENEMIES_CLEARED := {"result": VICTORY, "reason": REASON_ENEMIES_CLEARED}
const VICTORY_BOSS := {"result": VICTORY, "reason": REASON_BOSS}
const VICTORY_SCRIPT := {"result": VICTORY, "reason": REASON_SCRIPT}
const DEFEAT_FALLEN := {"result": DEFEAT, "reason": REASON_FALLEN}


static func victory(reason: String) -> Dictionary:
	assert(REASONS[VICTORY].has(reason), "unknown victory reason %s" % reason)
	return {"result": VICTORY, "reason": reason}


## The loop's outcome, `{}` while the battle is undecided.
static func of(loop: Dictionary) -> Dictionary:
	var outcome: Variant = loop.get("battle_outcome", {})
	return outcome if outcome is Dictionary else {}


static func decided(loop: Dictionary) -> bool:
	return not of(loop).is_empty()


static func won(loop: Dictionary) -> bool:
	return is_victory(of(loop))


static func lost(loop: Dictionary) -> bool:
	return is_defeat(of(loop))


static func is_victory(outcome: Dictionary) -> bool:
	return str(outcome.get("result", "")) == VICTORY


static func is_defeat(outcome: Dictionary) -> bool:
	return str(outcome.get("result", "")) == DEFEAT


static func reason(outcome: Dictionary) -> String:
	return str(outcome.get("reason", ""))


## "" for a well-formed outcome (`{}` or a listed result／reason pair), else the defect.
static func error(outcome: Variant) -> String:
	if not outcome is Dictionary: return "outcome_not_dictionary"
	if outcome.is_empty(): return ""
	if outcome.keys().size() != 2 or not outcome.get("result") is String or not outcome.get("reason") is String: return "outcome_shape"
	if not REASONS.has(outcome["result"]): return "unknown_outcome_result"
	if not REASONS[outcome["result"]].has(outcome["reason"]): return "unknown_outcome_reason"
	return ""


## Report-line spelling: `victory/escape`; "" while undecided. Never parsed back.
static func describe(outcome: Dictionary) -> String:
	if outcome.is_empty(): return ""
	return "%s/%s" % [str(outcome.get("result", "")), str(outcome.get("reason", ""))]
