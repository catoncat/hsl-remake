extends "res://tests/support/TestSuite.gd"

## Regression guards for the autoplay commander (tests/support/AutoplayBrain.gd), a test tool:
## only the behaviours whose loss would let the bot lose battles a player wins — it reads who
## must survive and whom to kill from the armed win／fail statuses (not a roster written into
## the bot), marches the hero only onto cells he survives, and drinks／cures when hurt. Its
## weights and thresholds are tuning, not contract, and are not pinned here.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Brain = preload("res://tests/support/AutoplayBrain.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")


func _init() -> void:
	tag = "AUTOPLAY_BRAIN_TESTS"


func run() -> void:
	_briefing()
	_objective_march()
	_heal_and_cure()
	Brain._envelope_cache.clear()


func _loop(path: String, level: int) -> Dictionary:
	var loop := Loop.create([], "", BattleScenario.load_file(path), level)
	_assert_true(bool(loop.get("scenario_ok", false)), "%s creates a PlayLoop (%s)" % [path.get_file(), str(loop.get("scenario_error", ""))])
	return loop


## `loop` with every unit in `ids` changed by `edit` (a copy; the fixture stays untouched).
func _edited(loop: Dictionary, ids: Array, edit: Callable) -> Dictionary:
	var next: Dictionary = Loop.copy(loop)
	for unit in next["units"]:
		if ids.has(str(unit["id"])): edit.call(unit)
	return next


func _fallen(loop: Dictionary, ids: Array) -> Dictionary:
	return _edited(loop, ids, func(unit): unit["hp"] = 0; unit["defeated"] = true)


## Target identification: the must-survive set follows the armed fail statuses (level 3's two
## `actCheckPlayer 1` statuses), the objective the armed win status (level 6's
## `actCheckEnemy,1,SID_ENEMY024`); disarming or firing a status changes the set.
func _briefing() -> void:
	var level3 := _loop("res://content/battles/battle_003.json", 3)
	var survivors := Brain.must_survive_ids(level3)
	survivors.sort()
	_assert_eq(survivors, ["leonard", "tina"], "level 3: the two actCheckPlayer 1 statuses name 雷歐納德 and 緹娜; 琥 may fall")
	var disarmed: Dictionary = Loop.copy(level3)
	disarmed["fail_statuses"] = []
	_assert_eq(Brain.must_survive_ids(disarmed), [], "no armed fail status: nobody is must-survive")
	_assert_eq(Brain.must_survive_ids(_fallen(level3, ["tina"])), ["leonard"], "level 3 with 緹娜 fallen: her status is firing, 雷歐納德 remains")
	var level6 := Loop.begin_battle(_loop("res://content/battles/battle_006.json", 6))
	_assert_eq(Brain.objective_target_ids(level6), ["guard024_1"], "level 6: the armed 打倒隊長 status names 隊長 guard024_1")
	var no_win: Dictionary = Loop.copy(level6)
	no_win["win_statuses"] = []
	_assert_eq(Brain.objective_target_ids(no_win), [], "level 6 without its win status: no objective")
	_assert_eq(Brain.objective_target_ids(Loop.begin_battle(_loop("res://content/battles/battle_005.json", 5))), [], "level 5: a clear-the-field status names no objective")


## Not into a lethal cell: level 6's captain stands out of reach and the objective plan is the
## march on him; the hero's planned cell is one the foes reaching it cannot kill him on.
func _objective_march() -> void:
	var level6 := Loop.begin_battle(_loop("res://content/battles/battle_006.json", 6))
	Brain._envelope_cache.clear()
	var board: Dictionary = Brain._board(level6)
	var march := {}
	for option in Brain.candidates(level6, board, 0, true):
		if str(option["id"]) == "objective:guard024_1": march = option
	_assert_true(not march.is_empty(), "level 6 opening: objective:guard024_1 is offered as the march on 隊長")
	if march.is_empty(): return
	var hero: Dictionary = board["hero"]
	var cell: Variant = Brain._planned_cell(march, str(hero["id"]))
	_assert_true(cell is Vector2i and Brain._worst_incoming(level6, hero, Brain._threatening(level6, board, hero, cell), true) < int(hero["hp"]), "雷歐納德 marches only onto a cell the foes reaching it cannot kill him on (%s)" % str(cell))


## Low HP drinks: 雷歐納德 at 1 HP beside a foe with a 回復藥 is offered heal:leonard; a
## poisoned hero is offered the cure, and grounding it through use_item clears the poison.
func _heal_and_cure() -> void:
	var level5 := Loop.begin_battle(_loop("res://content/battles/battle_005.json", 5))
	var hero: Dictionary = Loop.unit(level5, "leonard")
	var foe := {}
	for unit in level5["units"]:
		if str(unit.get("battle_actor_role", "")) == Loop.ROLE_ENEMY and not bool(unit.get("no_attack", false)):
			foe = unit
			break
	var beside := _edited(level5, [str(foe["id"])], func(unit): unit["coord"] = hero["coord"] + Vector2i(1, 0))
	beside = _edited(beside, ["leonard"], func(unit): unit["hp"] = 1; unit["inventory"] = [241, 0, 0, 0, 0, 0, 0, 0])
	Brain._envelope_cache.clear()
	_assert_eq(str(Brain._heal_candidate(beside, Brain._board(beside), true).get("target_id", "")), "leonard", "雷歐納德 at 1 HP beside a foe with a 回復藥 is offered heal:leonard")

	# The cure sits in the bag of the unit at the menu (level 5: someone acts before him).
	var acting := str(level5.get("selected_unit_id", ""))
	var poisoned := _edited(level5, ["leonard"], func(unit):
		unit["status_flags"] = int(unit["status_flags"]) | Brain.Status.POISON
		unit["status_counters"]["poison"] = (24 << 16) | 2
		unit["inventory"] = [241, 0, 0, 0, 0, 0, 0, 0])
	poisoned = _edited(poisoned, [acting], func(unit): unit["inventory"] = [246, 0, 0, 0, 0, 0, 0, 0])
	var board: Dictionary = Brain._board(poisoned)
	var cure := {}
	for option in Brain.candidates(poisoned, board, 0, true):
		if str(option["id"]) == "cure:leonard": cure = option
	_assert_true(acting != "leonard" and not cure.is_empty() and str(cure.get("healer_id", "")) == acting, "a poisoned 雷歐納德 is offered cure:leonard by %s, who holds the 解毒草" % acting)
	if cure.is_empty(): return
	var grounded: Dictionary = Brain._ground(poisoned, str(cure["healer_id"]), cure, RandomNumberGenerator.new())
	var cured := Loop.unit(grounded["loop"], "leonard")
	_assert_true(str(grounded["action"]) in ["use_item", "move_then_item"] and (int(cured["status_flags"]) & Brain.Status.POISON) == 0, "grounding cure:leonard uses the 解毒草 and clears his poison (action %s)" % str(grounded["action"]))
