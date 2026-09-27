extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const run_growth_lifecycle_tests = preload("res://tests/run_growth_lifecycle_tests.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WATER := "magic:magicWATER:magicCode01"
const CENTER := Vector2i(11,16)

func _init() -> void:
	tag = "WATER_STRIKE_TESTS"

static func fixture(learn: bool = true) -> Dictionary:
	var loop := run_growth_lifecycle_tests.fixture(3)
	BattlePlayLoop.unit_ref(loop,"tina")["coord"]=Vector2i(10,16)
	BattlePlayLoop.unit_ref(loop,"companion")["coord"]=Vector2i(10,15)
	var enemy := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	enemy["coord"]=Vector2i(12,16);enemy["ai_home_coord"]=enemy["coord"]
	var second:=enemy.duplicate(true)
	second["id"]="enemy021_2";second["coord"]=Vector2i(11,15);second["ai_home_coord"]=second["coord"]
	loop["units"].append(second)
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop=BattlePlayLoop.return_to_player(loop,"tina")
	if learn:loop=BattlePlayLoop.finish_exhausted_action(run_growth_lifecycle_tests.cast(loop,run_growth_lifecycle_tests.HEAL,"companion",zero))
	return loop

static func selected(loop:Dictionary) -> Dictionary:
	return BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop,"magic"),WATER)

static func cast(loop:Dictionary,rng:Variant=null) -> Dictionary:
	return BattlePlayLoop.attack_target(selected(loop),"enemy021_1",rng,CENTER)

func run() -> void:
	var loop:=fixture()
	check(loop["skill_book"]["skills"].has(WATER),"newly earned Water Strike must be a registered usable action")
	if not loop["skill_book"]["skills"].has(WATER):return
	native_cases()
	large_and_equipment()

func native_cases():
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_water_strike.json"))
	for row in packet["rolls"]:
		var draws:Array=row["draws"].duplicate(true)
		var actual:=BattlePlayLoop.StatusApplicationRules.Rolls.roll(row["input"],func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"water native full-return draw order")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(actual["value"]==int(row["native"]["value"]) and actual["hit_bonus_after"]==int(row["native"]["hit_bonus_after"]) and draws.is_empty(),"water helper equals original full return")
	for row in packet["applications"]:
		var c:Dictionary=row["input"]
		var target:Dictionary={"hp":int(c["hp"]),"status_flags":0,"status_counters":{"poison":0,"paralysis":0,"no_magic":0}}
		var draws:Array=row["draws"].duplicate(true)
		var actual:=BattlePlayLoop.StatusApplicationRules.resolve({"function_mask":1,"immunities":0,"roll_input":c},target,func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"water HP prefix consumes original draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(actual["target_changes"]["hp"]==int(row["native"]["hp"]) and actual["native_contribution"]==int(row["native"]["contribution"]) and draws.is_empty(),"water HP cap and contribution equal native prefix")

func large_and_equipment():
	var loop:=fixture()
	var giant:Dictionary=preload("res://tests/run_large_actor_tests.gd").source_large().duplicate(true)
	giant.merge({"id":"enemy021_1","coord":Vector2i(12,16),"hp":500,"max_hp":500},true)
	loop["units"]=loop["units"].filter(func(u):return u["battle_actor_role"]!=BattlePlayLoop.ROLE_ENEMY)
	loop["units"].append(giant)
	var before:=loop.duplicate(true)
	var after:=cast(loop,zero)
	check(BattlePlayLoop.Footprint.cells(giant).size()==9 and after["last_attack"]["affected_targets"].size()==1,"real source039 covering several cross cells takes exactly one target settlement")
	check(BattlePlayLoop.unit(after,"tina")["mp"]==BattlePlayLoop.unit(before,"tina")["mp"]-8 and BattlePlayLoop.unit(after,"enemy021_1")["hp"]==500-after["last_attack"]["actual_damage"],"large actor neither multiplies damage nor charges one cost per body cell")
	loop=fixture()
	var actor:=BattlePlayLoop.unit_ref(loop,"tina")
	actor["equipment"]=actor["equipment"].filter(func(s):return s["slot"]!="accessory1")
	actor["equipment"].append({"slot":"accessory1","item_code":218})
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["mp"]=4
	after=cast(loop,zero)
	check(after["last_attack"]["resource_payment"]["amount"]==4 and after["last_attack"]["affected_targets"].size()==2 and BattlePlayLoop.unit(after,"tina")["mp"]==0,"current inverse-cross equipment halves the one cast debit, not each target")
	loop=fixture();loop["moved_this_action"]=true
	var calls:=[0]
	after=cast(loop,func(_bound):calls[0]+=1;return 0)
	check(calls[0]==0 and after["units"]==loop["units"],"unpermitted moved water casting is rejected without draws")
	actor=BattlePlayLoop.unit_ref(loop,"tina")
	actor["equipment"]=actor["equipment"].filter(func(s):return s["slot"]!="accessory1")
	actor["equipment"].append({"slot":"accessory1","item_code":232})
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	check(cast(loop,zero)["last_attack"].get("skill_id")==WATER,"current movement ring permits the same water action after moving")
