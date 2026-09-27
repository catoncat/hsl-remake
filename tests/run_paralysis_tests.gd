extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const LoopCombat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const Entry = preload("res://game/sim/ActionEntryRules.gd")
const Cases = preload("res://tests/run_position_equipment_tests.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const Apply = preload("res://game/sim/StatusApplicationRules.gd")
const Items = preload("res://game/sim/ItemUseRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BIND := "magic:magicEARTH:magicCode05"

func _init() -> void:
	tag = "PARALYSIS_TESTS"

static func fixture(role: String = "026", ai: bool = false) -> Dictionary:
	var loop := Cases.fixture(role, ai)
	var actor := Loop._unit(loop, "leonard")
	actor["inventory"] = [211,248,232,227,31,12,241,0]
	actor["growth_profile"]["source"]["hit_point"] += 200
	actor["growth_profile"]["source"]["magic_point"] += 100
	actor["growth_profile"]["source"]["speed"] += 120
	actor["growth_profile"]["source"]["has_magic"] = true
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"]), true)
	actor["hp"] = actor["max_hp"]; actor["mp"] = actor["max_mp"]
	own(loop, "skill_book")["actors"][role]["supported_initial_ids"] = [BIND, Cases.WIND, Cases.HEAL, Cases.CURE]
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return loop if ai else Loop._return_to_player(loop,"leonard")

static func afflict(actor: Dictionary, turns: int = 2) -> void:
	actor.merge(Status.apply(actor,"paralysis",2)["changes"],true)
	actor["status_counters"]["paralysis"] = turns # Explicit remaining-time setup.

func run() -> void:
	native_cases()
	entry_and_restore()
	spell_and_equipment()
	aid_and_replanning()
	terminal_cases()
	await presentation_cases()

func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_paralysis.json"))
	for row in packet["entries"]:
		var c: Dictionary = row["input"]
		check(Entry.skips(int(c["flags"]),int(c["phase"]),bool(c["active"])) == row["native"]["skipped"],"native player/AI skip gate preserves nonfresh action phases")
	var base := fixture()
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var loop := base.duplicate(true)
		var actor := Loop._unit(loop,"leonard");var target := Loop._unit(loop,"enemy021_1")
		actor["level"] = int(c["level"]);actor["hit_bonus_accum"] = int(c["hit_bonus"])
		actor["combat_profile"].merge({"mind":int(c["mind"]),"live_magic_attack":int(c["magic_attack"])},true)
		actor["equipment"] = [{"slot":"accessory1","item_code":215}]
		target["equipment"] = [] if int(c["effects"]) == 0 else [{"slot":"accessory1","item_code":229 if int(c["effects"]) == 0x80 else 211}]
		own(loop, "skill_book")["actors"][target["actor_id"]]["status_capability_flags"] = 2 if c["no_attack"] else 0
		target["combat_profile"]["resist_by_type"]["0"] = int(c["resistance"])
		target.merge({"hp":int(c["hp"]),"status_flags":3|(4 if c["turns"] else 0),"status_counters":{"poison":0x70003,"no_magic":2,"paralysis":int(c["turns"])}},true)
		var prepared := Apply.prepare(actor,target,Loop.skill_fields(loop,BIND),loop["skill_book"],loop["skill_target_data"],loop["equipment_items"])
		check(prepared["ok"],"source paralysis inputs prepare")
		if not prepared["ok"]:continue
		var draws: Array = row["draws"].duplicate(true)
		var result := Apply.resolve(prepared,target,func(bound):
			check(not draws.is_empty() and bound == int(draws[0]["bound"]),"original paralysis draw order/bound")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(draws.is_empty() and result["native_contribution"] == int(row["native"]["contribution"]),"original actual added-duration contribution, including zero at cap")
		check(result["target_changes"]["status_counters"]["paralysis"] == int(row["native"]["turns"]) and result["target_changes"]["status_flags"] == int(row["native"]["flags"]),"original paralysis application/immune result")
		check(result["target_changes"]["hp"] == target["hp"] and result["target_changes"]["status_counters"]["poison"] == 0x70003 and result["target_changes"]["status_counters"]["no_magic"] == 2,"binding never invents HP damage or clears unrelated statuses")
	for row in packet["ticks"]:
		var counters := {};var flags := 0
		for key in row["input"]:
			counters[key] = int(row["input"][key])
			if counters[key]:flags |= int(Status.COUNTERS[key])
		var result := Status.after_action({"hp":100,"status_flags":flags,"status_counters":counters})
		check(result["ok"],"all three native counters prepare")
		for key in counters:check(result["changes"]["status_counters"][key] == int(row["native"][key]),"normal-return counter expiry agrees with original")
	for row in packet["cures"]:
		if int(row["input"]["effects"]) != 0x20000000:continue
		var actor := Loop.unit(base,"leonard")
		actor.merge({"status_flags":3|(4 if row["input"]["turns"] else 0),"status_counters":{"poison":0x70003,"no_magic":2,"paralysis":int(row["input"]["turns"])}},true)
		var effect := Items.prepare(actor,base["consumables"]["248"])
		check(effect["ok"] == (int(row["input"]["turns"]) > 0),"real cure rejects a healthy target without spending the item")
		if effect["ok"]:check(effect["changes"]["status_flags"] == int(row["native"]["flags"]) and effect["changes"]["status_counters"]["paralysis"] == 0 and effect["changes"]["status_counters"]["poison"] == 0x70003,"native cure clears only paralysis")
	for row in packet["scans"]:
		if row["input"]["slots"].has(251.0):continue # Native multi-cure item is not enabled in this product subset.
		var slots: Array = row["input"]["slots"].map(func(n):return int(n))
		var selected := Items.first_status_slot(slots,base["consumables"],int(row["input"]["mask"]))
		check(selected["ok"] and selected["index"]+1 == int(row["native"]),"native eight-slot matching status-cure order")
	check(not Loop.unit(BattleFixture.loop(),"leonard")["inventory"].has(248),"registered cure is not a default inventory grant")

func entry_and_restore() -> void:
	for ai in [false,true]:
		for wings in [false,true]:
			var loop := fixture("026",ai);var actor := Loop._unit(loop,"leonard")
			actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
			if wings:actor["equipment"].append({"slot":"accessory1","item_code":227})
			afflict(actor);actor.merge(Status.apply(actor,"poison",3,7)["changes"],true)
			if not ai:loop=Loop._return_to_player(loop,"leonard")
			var original := loop.duplicate(true)
			check(loop["interaction"] == "ai_resolving" and not Loop.command_available(loop,"wait"),"paralyzed player and AI share automatic fresh-entry path")
			var saved := Checkpoint.encode(loop,Cases.VIEW)
			check(saved["ok"],"unprocessed paralysis entry can be serialized")
			var result := Loop.step_ai_turn(loop,no_rng)
			check(result["scenario_ok"] and result["last_ai_action"]["kind"] == "paralysis_skip" and result["turn_queue"]["index"] == 1,"one skip hands to the next real queue actor")
			check(not result["extra_action"]["pending"] and result["action_end_sequence"] == 1 and result["last_ai_actions"].size() == 1,"wings cannot turn a paralysis skip into two waits or two tails")
			var after := Loop.unit(result,"leonard")
			check(after["status_counters"]["paralysis"] == 1 and after["hp"] == actor["hp"]-7 and after["exp"] == actor["exp"] and after["stamina"] == actor["stamina"],"skip ticks poison and duration exactly once without offense/EXP/ST")
			check(loop == original,"entry proposal never mutates its caller")
			if saved["ok"]:
				var restored := Checkpoint.decode(saved["bytes"], loop)
				check(restored["ok"] and Loop.step_ai_turn(restored["snapshot"]["loop"],no_rng) == result,"restoring before entry produces one identical skip, not a repeated old action")
	var all := fixture()
	for actor in all["units"]:afflict(actor,1)
	all=Loop._return_to_player(all,"leonard")
	for _i in range(3):all=Loop.step_ai_turn(all,no_rng)
	check(all["selected_unit_id"] == "leonard" and all["turn"] == 2 and all["action_end_sequence"] == 3,"entire immobilized roster advances once and returns normal control after expiry")
	check(all["units"].all(func(a):return not Status.paralyzed(a)) and Loop.command_available(all,"move"),"expiry restores the next normal action instead of granting a late extra turn")
	var skipped := fixture();var actor := Loop._unit(skipped,"leonard")
	afflict(actor,1);actor["equipment"].append({"slot":"armor-extra-invalid","item_code":227})
	var bad := Loop.step_ai_turn(Loop._return_to_player(skipped,"leonard"),no_rng)
	check(not bad["scenario_ok"] and bad["units"] == skipped["units"] and bad["action_end_sequence"] == 0,"invalid equipment/entry state cannot partially tick or advance")

func spell_and_equipment() -> void:
	var loop := fixture();var actor := Loop._unit(loop,"leonard");var first := Loop._unit(loop,"enemy021_1")
	actor["exp"] = 99;first["coord"] = Vector2i(11,8)
	first["equipment"] = [{"slot":"accessory1","item_code":211}]
	var second := first.duplicate(true);second.merge({"id":"bound-second","coord":Vector2i(10,9),"equipment":[]},true)
	loop["units"].append(second)
	var mp_before: int = actor["mp"]
	var receipt := LoopCombat._resolve_skill(loop,"leonard",first["id"],BIND,Loop.skill_fields(loop,BIND),actor["coord"],zero,Vector2i(10,8))
	check(not receipt.is_empty() and receipt["affected_targets"].size() == 2,"source cross effect accepts an empty center and real multiple targets")
	if receipt.is_empty():return
	check(not Status.paralyzed(first) and Status.paralyzed(second) and actor["mp"] == mp_before-16,"mixed immunity is per target and the action pays once")
	check(actor["level"] == 2 and receipt.has("experience") and receipt["damage"] == 0,"paralysis contribution enters final EXP and role growth without fictitious damage")
	var attacker := fixture("001");var unit := Loop._unit(attacker,"leonard");var victim := Loop._unit(attacker,"enemy021_1")
	attacker=Cases.equip(attacker,"weapon",12);unit=Loop._unit(attacker,"leonard");victim=Loop._unit(attacker,"enemy021_1")
	unit["hit_bonus_accum"]=1000;victim["coord"]=Vector2i(9,8);victim["no_attack"]=false;victim["combat_profile"]["attack_back"]=100;afflict(victim)
	var exchange := LoopCombat._resolve_exchange(attacker,"leonard",victim["id"],zero)
	check(exchange["counter"].is_empty() and Loop.CombatSequence.participant_strikes(exchange).size()==2 and Status.paralyzed(victim),"paralyzed defender cannot counter a double series and damage does not fabricate a cure")
	for role in ["001","024","026"]:
		var equipped := Cases.equip(fixture(role),"accessory1",211)
		var owner := Loop._unit(equipped,"leonard")
		check(Apply.modifiers(owner,equipped["skill_book"],equipped["equipment_items"])["effects"] & 0x4000000,"source ring protects current eligible job")
		afflict(owner)
		var refreshed := Loop.ProgressionRules.refresh_growth_stats(owner,equipped["equipment_items"])
		check(Status.paralyzed(refreshed) and refreshed["status_counters"] == owner["status_counters"],"protection and growth refresh do not cure existing paralysis")
	var heavy := Cases.equip(fixture("024"),"weapon",31)
	check(Loop.EquipmentRules.equipped_code(Loop.unit(heavy,"leonard")["equipment"],"weapon")==31,"source heavy class may equip protected axe")
	check(Cases.equip(fixture("026"),"weapon",31)==fixture("026"),"mage cannot bypass original axe job restriction")

func aid_and_replanning() -> void:
	var support := Cases.equip(fixture(),"accessory2",227)
	var bound := Loop._unit(support,"enemy023_1")
	bound["coord"] = Vector2i(10,8);bound["hp"] = 4;afflict(bound)
	bound.merge(Status.apply(bound,"poison",3,7)["changes"],true)
	bound.merge(Status.apply(bound,"no_magic",2)["changes"],true)
	var counters: Dictionary = bound["status_counters"].duplicate(true)
	var healed := Loop.attack_target(Cases.selected(support,Cases.HEAL),bound["id"],zero)
	healed = Loop.finish_exhausted_action(healed) # The live scene calls this only after the support/EXP presentation.
	check(healed["last_attack"].get("healing",0)>0 and healed["extra_action"]["pending"] and Loop.unit(healed,bound["id"])["status_counters"]==counters,"first support action heals a paralyzed patient without curing or ticking any status")
	var cured := Loop.attack_target(Cases.selected(healed,Cases.CURE),bound["id"],zero)
	cured = Loop.finish_exhausted_action(cured)
	check(Loop.unit(cured,bound["id"])["status_counters"]=={"poison":0,"paralysis":2,"no_magic":2} and cured["interaction"]=="ai_resolving","second support action cures poison alone; the bound patient still takes the automatic entry path")
	var skipped := Loop.step_ai_turn(cured,no_rng)
	check(Loop.unit(skipped,bound["id"])["status_counters"]=={"poison":0,"paralysis":1,"no_magic":1} and Loop.unit(skipped,bound["id"])["hp"]==Loop.unit(cured,bound["id"])["hp"],"the now poison-free patient skips once without replaying damage/healing or either support reward")
	# Use the actual source owner for the caster-state check; patients may not own Binding.
	var disabled := Loop.unit(support,"leonard");afflict(disabled)
	var unavailable := Loop.SkillResolutionRules.available(disabled,BIND,Loop.skill_fields(support,BIND),support["skill_book"],support["skill_target_data"],support["equipment_items"])
	check(not unavailable["ok"] and unavailable["reason"]=="caster_paralyzed","ownership and resources cannot bypass caster paralysis")
	var loop := fixture();var ally := Loop._unit(loop,"enemy023_1")
	ally["coord"] = Vector2i(10,8);afflict(ally);ally.merge(Status.apply(ally,"no_magic",2)["changes"],true)
	loop=Cases.moved(loop,Vector2i(9,8))
	var use := Loop.use_item(loop,"248","enemy023_1",Loop.unit(loop,"leonard")["inventory"].find(248))
	check(use["last_item_use"].get("cured_paralysis",false) and not Status.paralyzed(Loop.unit(use,"enemy023_1")) and Status.magic_blocked(Loop.unit(use,"enemy023_1")),"actual move-then-item releases only paralysis before ally acts")
	check(use["selected_unit_id"]=="enemy023_1" and not Loop.unit(use,"leonard")["inventory"].has(248),"cure item debits once and restores next actor control")
	var ai := fixture("026",true);var medic := Loop._unit(ai,"leonard");var patient := Loop._unit(ai,"enemy023_1")
	medic["inventory"]=[248,0,0,0,0,0,0,0];medic["mp"]=0;patient["coord"]=Vector2i(12,8);afflict(patient)
	Loop._unit(ai,"enemy021_1")["coord"] = Vector2i(17,18) # Preserve a reachable aid route, not an occupied corridor.
	own(ai, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_help_otherhp":0,"ai_help_status":100,"ai_check_dying":0,"ai_help_selfhp":0},true)
	var prep := LoopAI._prepare_ai_turn(ai,"leonard")
	check(prep["ok"] and prep["ally_support"]["status_items"].has(patient["id"]),"AI with no mana plans actual cure-item aid: "+str(prep.get("reason","")))
	if not prep["ok"] or not prep["ally_support"]["status_items"].has(patient["id"]):return
	var plan: Dictionary = prep["ally_support"]["status_items"][patient["id"]]
	for changed in ["blocked","dead","cured","spent","paralyzed"]:
		var bad := ai.duplicate(true)
		if changed=="blocked":own(bad, "tiles")[plan["destination"]]={"blocks_movement":true}
		elif changed=="dead":Loop._unit(bad,patient["id"]).merge({"hp":0,"defeated":true},true)
		elif changed=="cured":Loop._unit(bad,patient["id"]).merge(Status.cure_paralysis(Loop.unit(bad,patient["id"])),true)
		elif changed=="spent":Loop._unit(bad,"leonard")["inventory"][0]=0
		else:afflict(Loop._unit(bad,"leonard"))
		var original := bad.duplicate(true)
		check(LoopAI._execute_ai_support_item(bad,"leonard",plan).is_empty() and bad==original,"stale aid rejects before position/inventory/effect mutation: "+changed)
	var done := Loop.step_ai_turn(ai,zero)
	check(done["scenario_ok"] and done["last_ai_action"]["kind"] == "move_then_item" and not Status.paralyzed(Loop.unit(done,patient["id"])) and done["selected_unit_id"]==patient["id"],"AI follows path, cures, then returns actual patient control")

func terminal_cases() -> void:
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var loop := fixture("001");var actor := Loop._unit(loop,"leonard");var enemy := Loop._unit(loop,"enemy021_1")
		if outcome==BattleOutcome.VICTORY_ESCAPE:
			actor["coord"]=loop["escape_zone"][0];afflict(actor,1);loop=Loop._return_to_player(loop,"leonard")
			var skip:=Loop.step_ai_turn(loop,no_rng)
			# Existing script arrival checks the committed position, not the label
			# of the preceding action. Terminal detection must precede the tail.
			check(skip["battle_outcome"]==outcome and skip["action_end_sequence"]==0 and Loop.unit(skip,"leonard")["status_counters"]["paralysis"]==1,"committed arrival wins before a skipped actor can tick statuses or resources")
			loop=skip
		elif outcome==BattleOutcome.VICTORY_ENEMIES_CLEARED:
			enemy["coord"]=Vector2i(9,8);enemy["hp"]=1;afflict(enemy);actor["hit_bonus_accum"]=1000
			loop=Loop.attack_target(Loop.choose_command(loop,"attack"),enemy["id"],zero)
		else:
			afflict(actor);actor["hp"]=1;enemy["coord"]=Vector2i(9,8);enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000
			enemy["combat_profile"]["live_attack_damage"]=1000
			var hit:=LoopCombat._resolve_exchange(loop,enemy["id"],"leonard",zero)
			check(not hit.is_empty() and hit["counter"].is_empty(),"lethal attacker receives no paralyzed counter")
			loop=Loop._resolve_outcome(loop)
		check(loop["battle_outcome"]==outcome and Checkpoint.encode(loop,Cases.VIEW)["ok"],"terminal state serializes complete paralysis state: "+BattleOutcome.describe(outcome))
		check(Loop.step_ai_turn(loop,no_rng)==loop and Loop.finish_exhausted_action(loop)==loop,"terminal cannot tick/restore/advance again")
		for unit in loop["units"]:
			if unit["defeated"]:check(unit["status_counters"]["paralysis"]==0,"death clears paralysis without resurrecting the actor")

func presentation_cases() -> void:
	var cue=preload("res://game/battle/scene/BattleTurnEndCue.gd").new();root.add_child(cue)
	var loop:=fixture();afflict(Loop._unit(loop,"leonard"),1)
	loop=Loop.step_ai_turn(Loop._return_to_player(loop,"leonard"),no_rng)
	var before:=loop.duplicate(true)
	cue.refresh(loop,Vector2(320,240),true,0)
	check(cue.label.text=="麻痺解除" and cue.busy(loop),"expiry is a finite status message, not a fake zero-resource value")
	cue.refresh(loop,Vector2(320,240),true,cue.NUMBER_SECONDS)  # a lone number lives 46 ticks
	check(not cue.busy(loop) and loop==before,"expiry display never advances state or queue")
	cue.queue_free();await process_frame
	var presentation=preload("res://game/battle/scene/BattlePresentation.gd").new()
	root.add_child(presentation)
	var quiet:=fixture();var prior:=quiet.duplicate(true)
	check(presentation.show_item_use({"sequence":1,"restored_hp":0,"cured_poison":false,"cured_paralysis":true},Vector2(320,240)),"new cure receipt starts actual item feedback")
	check(presentation.item_feedback_busy() and presentation.combat_busy(quiet),"the shared input/result gate includes a cure with no following resource events")
	await tree.create_timer(0.8).timeout
	check(not presentation.combat_busy(quiet) and quiet==prior,"finite item feedback releases controls without changing the transaction")
	check(not presentation.show_item_use({"sequence":1,"restored_hp":0,"cured_poison":false,"cured_paralysis":true},Vector2(320,240)),"same item sequence cannot restart the cure message")
	presentation.queue_free();await process_frame
