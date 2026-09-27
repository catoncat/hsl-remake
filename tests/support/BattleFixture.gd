extends RefCounted

## The reviewed level-51 formation as a pure-loop fixture: content/battles/first_battle.json
## (rule_adapter development_battle, unit ids leonard / enemy021_N / enemy026_N / enemy023_N /
## enemy024_N, the legacy escape cell [14,10]). The mechanics suites build their loops on
## this roster; it is not the playable first battle, which is content/battles/battle_051.json
## assembled by level_battle:51 and interpreted by WinfailScenarioRules like every other level.
##
## Process cache: create() over the fixture costs about ten times a deep copy of its result, and
## the rule suites share one run_all.gd process, so the parsed scenario and the default-roster
## loop per reward seed are built once per process. Callers only ever receive a duplicate(true)
## — a suite editing its fixture in place (state or configuration) cannot reach the cached
## original or another caller's copy. A caller-supplied roster or terrain path always runs
## create() (a test may rewrite the same terrain file between calls).

const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopConfig = preload("res://game/sim/BattleLoopConfig.gd")

const PATH := "res://content/battles/first_battle.json"
const SCHEMA := "hsl_development_battle.v1"

static var _scenario: Dictionary = {}
## reward_seed -> the loop create() built for the default roster and terrain; never handed out.
static var _loops: Dictionary = {}


static func scenario() -> Dictionary:
	if _scenario.is_empty():
		_scenario = BattleScenario.load_file(PATH, SCHEMA)
	return _scenario.duplicate(true)


## Loop.create over the fixture; `units` / `terrain_path` override the roster and terrain the
## same way the PlayLoop's own signature does.
static func loop(units: Array = [], terrain_path: String = "", reward_seed: int = 1) -> Dictionary:
	if not units.is_empty() or terrain_path != "":
		return Loop.create(units, terrain_path, scenario(), reward_seed)
	if not _loops.has(reward_seed):
		_loops[reward_seed] = Loop.create([], "", scenario(), reward_seed)
	var fresh: Dictionary = (_loops[reward_seed] as Dictionary).duplicate(true)
	# create() registers its configuration blocks with the run_all.gd freeze; the copy's own
	# blocks are the ones the suite can write, so they are registered in its place.
	if LoopConfig.freeze_enabled:
		LoopConfig.freeze(fresh)
	return fresh
