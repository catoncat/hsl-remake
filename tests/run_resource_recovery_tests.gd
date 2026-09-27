extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const run_job_stats_tests = preload("res://tests/run_job_stats_tests.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const TurnEndRules = preload("res://game/sim/TurnEndRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
const WIND := "magic:magicAIR:magicCode01"


func _init() -> void:
	tag = "RESOURCE_RECOVERY_TESTS"


static func equip(loop: Dictionary, slot: String, code: int) -> Dictionary:
	return BattlePlayLoop.change_equipment(loop,slot,BattlePlayLoop.unit(loop,"leonard")["inventory"].find(code) if code else -1,code)


func run() -> void:
	native_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_resource_recovery.json"))
	for row in packet["prefixes"]:
		var c: Dictionary = row["input"]
		var actual := 0
		if c["enabled"] and c["current"] < c["maximum"]:
			actual = ResourceRecoveryRules.amount(c["kind"],int(c["maximum"]),int(c["current"]),int(row["draws"][0]["value"]))
		check(actual == row["native"]["amount"], "native small-resource additive floor and actual missing-value cap")
	var actor := BattlePlayLoop.unit(run_job_stats_tests.fixture("026"),"leonard")
	actor["hp"] = actor["max_hp"];actor["mp"] = actor["max_mp"]
	var flags := {"mp_use_half":true,"hp_auto_restore":true,"mp_auto_restore":true,"hp_transfer_mp":false}
	var start := DamageRandomStream.seeded(19)
	var unchanged := ResourceRecoveryRules.prepare(actor,flags,start)
	check(unchanged["state"] == start and unchanged["draws"].is_empty() and unchanged["events"].is_empty(), "full bars cannot consume recovery RNG or generate fake feedback")
	actor["hp"] = 0
	check(not ResourceRecoveryRules.prepare(actor,flags,start)["ok"], "recovery never resurrects a defeated unit")
