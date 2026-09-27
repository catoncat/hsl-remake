extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_job_stats_tests.gd")
const Recovery = preload("res://game/sim/ResourceRecoveryRules.gd")
const Tail = preload("res://game/sim/TurnEndRules.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
const WIND := "magic:magicAIR:magicCode01"


func _init() -> void:
	tag = "RESOURCE_RECOVERY_TESTS"


static func equip(loop: Dictionary, slot: String, code: int) -> Dictionary:
	return Loop.change_equipment(loop,slot,Loop.unit(loop,"leonard")["inventory"].find(code) if code else -1,code)


func run() -> void:
	native_cases()
	transactions()
	ai_cases()
	save_and_terminal_cases()
	await cue_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_resource_recovery.json"))
	for row in packet["prefixes"]:
		var c: Dictionary = row["input"]
		var actual := 0
		if c["enabled"] and c["current"] < c["maximum"]:
			actual = Recovery.amount(c["kind"],int(c["maximum"]),int(c["current"]),int(row["draws"][0]["value"]))
		check(actual == row["native"]["amount"], "native small-resource additive floor and actual missing-value cap")
	var actor := Loop.unit(Cases.fixture("026"),"leonard")
	actor["hp"] = actor["max_hp"];actor["mp"] = actor["max_mp"]
	var flags := {"mp_use_half":true,"hp_auto_restore":true,"mp_auto_restore":true,"hp_transfer_mp":false}
	var start := DamageRandom.seeded(19)
	var unchanged := Recovery.prepare(actor,flags,start)
	check(unchanged["state"] == start and unchanged["draws"].is_empty() and unchanged["events"].is_empty(), "full bars cannot consume recovery RNG or generate fake feedback")
	actor["hp"] = 0
	check(not Recovery.prepare(actor,flags,start)["ok"], "recovery never resurrects a defeated unit")


func transactions() -> void:
	var loop := Cases.fixture("026")
	loop = equip(equip(loop,"accessory1",223),"accessory2",224)
	var actor := Loop._unit(loop,"leonard")
	actor["hp"] = 10; actor["mp"] = 0
	actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	var before := loop.duplicate(true)
	var done := Loop.choose_command(loop,"wait")
	var tail: Dictionary = done["last_action_end"]
	check(done["selected_unit_id"] == "enemy023_1" and done["turn_queue"]["index"] == 1 and before == loop, "one final-action transaction hands off once without mutating the caller")
	check(tail["events"].map(func(e):return e["kind"]) == ["poison","auto_hp","auto_mp"], "poison precedes HP then MP restoration")
	check(tail["events"][0]["after"] == 3 and tail["after"]["hp"] > 3 and tail["after"]["mp"] > 0, "actual final bars use poison-floor result and current derived caps")
	check(Loop.unit(done,"leonard")["status_counters"]["no_magic"] == 1 and tail["draws"].size() == 2, "silence does not prevent passive regeneration and still decays once")
	check(done["gold"] == before["gold"] and no_draw(done, before, "reward") and Loop.unit(done,"leonard")["exp"] == actor["exp"], "passive restoration grants no XP, gold or reward reroll")
	var wings := equip(Cases.fixture("026"),"accessory1",227)
	wings = equip(wings,"accessory2",224)
	Loop._unit(wings,"leonard")["mp"] = 0
	var first := Loop.choose_command(wings,"wait")
	check(first["extra_action"]["pending"] and first["action_end_sequence"] == 0 and no_draw(first, wings, "damage") and Loop.unit(first,"leonard")["mp"] == 0, "first of two actions performs no passive restoration or RNG")
	var second := Loop.choose_command(first,"wait")
	check(second["action_end_sequence"] == 1 and second["last_action_end"]["events"].size() == 1 and Loop.unit(second,"leonard")["mp"] > 0, "only second completed action owns recovery")
	var removed := equip(first,"accessory2",0)
	var no_regen := Loop.choose_command(removed,"wait")
	check(no_draw(no_regen, first, "damage") and Loop.unit(no_regen,"leonard")["mp"] == 0, "removing recovery before the final action immediately disables it without resetting Wings")
	var half := equip(Cases.fixture("026"),"accessory1",218)
	var caster := Loop._unit(half,"leonard")
	var price := int(Loop.skill_fields(half,WIND)["expend"]) / 2
	caster["mp"] = price
	var quote := Loop.SkillResolutionRules.available(caster,WIND,Loop.skill_fields(half,WIND),half["skill_book"],half["skill_target_data"],half["equipment_items"])
	check(quote["ok"], "actual half-MP equipment makes a source spell affordable")
	var hit := Loop.attack_target(Loop.choose_magic(Loop.choose_command(half,"magic"),WIND),"enemy021_1",zero)
	check(hit.has("last_combat") and Loop.unit(hit,"leonard")["mp"] == 0, "source spell commits one independent reduced MP debit")
	var duplicate := half.duplicate(true)
	Loop._unit(duplicate,"leonard")["equipment"].append({"slot":"accessory2","item_code":218})
	check(Loop.SkillResourceRules.quote(Loop.unit(duplicate,"leonard"),{"expend":7},"magic",duplicate["equipment_items"])["amount"] == 3, "two reduction sources do not quarter the cost")
	var free := equip(Cases.fixture("026"),"accessory2",224)
	var free_before := free.duplicate(true)
	var selected := Loop.choose_command(free,"move")
	selected = Loop.cancel_interaction(selected)
	check(selected["action_end_sequence"] == 0 and no_draw(selected, free_before, "damage"), "select/cancel and free equipment never cause a recovery tick")


func ai_cases() -> void:
	var loop := Cases.fixture("026",false)
	var actor := Loop._unit(loop,"leonard")
	actor["equipment"].append({"slot":"accessory2","item_code":224})
	actor["mp"] = 0; actor["no_attack"] = true
	own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_att_magic":100,"ai_help_selfhp":0,"ai_check_dying":0,"find_range":20},true)
	for id in ["magic:magicAIR:magicCode01", "magic:magicFIRE:magicCode01"]: own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "100"
	var first := Loop.step_ai_turn(loop,zero)
	check(first["scenario_ok"] and not first["last_ai_action"].has("skill_id") and Loop.unit(first,"leonard")["mp"] >= 2, "empty-MP AI falls back and recovers only at its final boundary")
	# Re-enter the same actor through a new ordinary queue cycle, not a repeated receipt.
	var accepted := false
	for _turn in range(6):
		first["turn_queue"] = Loop.CoreTurnQueue.rebuild(first["units"])
		first = Loop.step_ai_turn(Cases.ai_start(first),zero)
		if first["last_ai_action"].has("skill_id"):
			accepted = first["last_ai_action"].has("resource_payment")
			break
	check(first["scenario_ok"] and accepted, "a later AI decision observes sufficiently restored MP and builds a new legal cast")


func save_and_terminal_cases() -> void:
	var loop := equip(Cases.fixture("026"),"accessory1",224)
	Loop._unit(loop,"leonard")["mp"] = 0
	var done := Loop.choose_command(loop,"wait")
	var encoded := Checkpoint.encode(done,VIEW)
	check(encoded["ok"], "completed resource-tail snapshot is serializable")
	if encoded["ok"]:
		var restored := Checkpoint.decode(encoded["bytes"], done)
		check(restored["ok"] and restored["snapshot"]["loop"] == done and Loop.finish_exhausted_action(done) == done, "restore/repeated offense finish cannot repeat recovery, XP or RNG")
	for mode in ["rng","effect"]:
		var bad := done.duplicate(true)
		if mode == "rng": set_stream(bad, "damage", [0])
		else: own(bad, "equipment_items")["224"]["mp_auto_restore"] = 1
		check(not Checkpoint.encode(bad,VIEW)["ok"], "corrupt recovery state refused: "+mode)
		var result := Loop.attack_target(Loop.choose_command(bad,"attack"),"enemy021_1",no_rng)
		check(result["units"] == bad["units"] and result["turn_queue"] == bad["turn_queue"], "invalid tail data cannot partially spend a new action")
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var terminal := loop.duplicate(true)
		if outcome == BattleOutcome.DEFEAT_FALLEN: Loop._set_unit_defeated(terminal,"leonard",true)
		elif outcome == BattleOutcome.VICTORY_ENEMIES_CLEARED: Loop._set_unit_defeated(terminal,"enemy021_1",true)
		else: Loop._unit(terminal,"leonard")["coord"] = terminal["escape_zone"][0]
		terminal = Loop._resolve_outcome(terminal)
		check(terminal["battle_outcome"] == outcome and terminal["action_end_sequence"] == 0 and no_draw(terminal, loop, "damage"), "terminal result suppresses regeneration and revival: "+BattleOutcome.describe(outcome))
		check(Loop.choose_command(terminal,"wait") == terminal and Checkpoint.encode(terminal,VIEW)["ok"], "terminal saved state remains frozen")


func cue_cases() -> void:
	var cue = preload("res://game/battle/scene/BattleTurnEndCue.gd").new()
	root.add_child(cue)
	var loop := equip(equip(Cases.fixture("026"),"accessory1",223),"accessory2",224)
	var actor := Loop._unit(loop,"leonard")
	actor["hp"] = 10;actor["mp"] = 0
	actor.merge(Loop.StatusEffectRules.apply(actor,"poison",2,7)["changes"],true)
	loop = Loop.choose_command(loop,"wait")
	var before := loop.duplicate(true)
	check(cue.busy(loop), "pending tail feedback blocks next actor before the first frame")
	cue.refresh(loop,Vector2(320,240),false,10)
	check(cue.pending(loop) and not cue.label.visible, "previous combat cannot consume pending recovery invisibly")
	for index in range(3):
		cue.refresh(loop,Vector2(320,240),true,0 if index == 0 else cue.EVENT_SECONDS)
		check(cue.cursor == index and cue.showing() and cue.busy(loop), "ordered finite poison/HP/MP visible beat")
	cue.refresh(loop,Vector2(320,240),true,cue.NUMBER_SECONDS)  # last number lives 46 ticks
	check(not cue.busy(loop) and not cue.showing() and loop == before, "tail releases input without changing battle state")
	cue.finish(loop);cue.refresh(loop,Vector2.ZERO,true,0)
	check(not cue.busy(loop), "loading an already-settled tail does not replay its feedback")
	cue.queue_free();await process_frame
