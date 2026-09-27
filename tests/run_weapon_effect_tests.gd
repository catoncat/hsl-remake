extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const WeaponEffectRules = preload("res://game/sim/WeaponEffectRules.gd")
const run_large_actor_tests = preload("res://tests/run_large_actor_tests.gd")
const run_position_equipment_tests = preload("res://tests/run_position_equipment_tests.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var replay: Array = []
var draw_index := 0


func _init() -> void:
	tag = "WEAPON_EFFECT_TESTS"


static func set_gear(actor: Dictionary, catalog: Dictionary, slot: String, code: int) -> void:
	actor["equipment"] = actor["equipment"].filter(func(e): return e["slot"] != slot)
	if code: actor["equipment"].append({"slot": slot, "item_code": code, "name": catalog[str(code)]["name"]})
	actor["equipment"].sort_custom(func(a,b): return BattlePlayLoop.EquipmentRules.SLOTS.find(a["slot"]) < BattlePlayLoop.EquipmentRules.SLOTS.find(b["slot"]))
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor, catalog), true)
	if slot == "weapon" and code: actor["weapon_code"] = code


static func fixture(code: int = 35, twice: bool = false, counter: bool = false) -> Dictionary:
	var loop := run_large_actor_tests.fixture()
	var actor := BattlePlayLoop.unit_ref(loop,"leonard")
	set_gear(actor,loop["equipment_items"],"weapon",code)
	if twice: set_gear(actor,loop["equipment_items"],"accessory2",227)
	actor["hp"]=actor["max_hp"];actor["hit_bonus_accum"]=1000
	actor["inventory"]=[29,35,37,229,227,246,248,0]
	var target := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	target.merge({"coord":Vector2i(8,6),"hp":5000,"max_hp":5000,"no_attack":not counter,"live_speed":5,"hit_bonus_accum":1000},true)
	target["combat_profile"]["attack_back"]=100
	# Real queue slots: attacker first, observer second, target last. The observer
	# lets a save retain a cancelled target before advancing through its old slot.
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild([
		{"id":"leonard","live_speed":300,"action_ready":true},
		{"id":"enemy023_1","live_speed":200,"action_ready":true},
		{"id":"enemy021_1","live_speed":5,"action_ready":true}])
	return BattlePlayLoop.return_to_player(loop,"leonard")


func run() -> void:
	native_replay()
	series_transactions()
	queue_lifecycle()
	gear_and_support()
	status_word()
	phase_cancellation()


func native_replay() -> void:
	var packet: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_weapon_effects.json"))
	var original:=fixture()
	for row in packet["effects"]:
		var c:Dictionary=row["input"];var loop:=original.duplicate(true)
		var actor:=BattlePlayLoop.unit_ref(loop,"leonard");var target:=BattlePlayLoop.unit_ref(loop,"enemy021_1")
		actor["id"]="0";target["id"]="1"
		own(loop, "equipment_items")["35"]["weapon_effect_flags"]=int(c["effects"])
		own(loop, "equipment_items")["229"]["status_effect_flags"]=int(c["immunity"])
		target["equipment"].append({"slot":"accessory1","item_code":229})
		target["hp"]=int(c["hp"]);target["mp"]=77
		target["status_flags"]=6 | (1 if c["poison"] else 0)
		target["status_counters"]={"poison":int(c["poison"]),"paralysis":2,"no_magic":3}
		var queue:={"index":int(c["index"]),"round":0,"slots":[]}
		for slot in c["slots"]:queue["slots"].append({"id":str(int(slot[0])),"enabled":bool(slot[1])})
		var before:=target.duplicate(true);var before_queue:=queue.duplicate(true)
		var prepared:=WeaponEffectRules.prepare(actor,target,loop["skill_book"],loop["equipment_items"],queue)
		check(prepared["ok"],"native equipment and target proposal validates")
		replay=row["draws"];draw_index=0
		var result:=WeaponEffectRules.resolve(prepared,native_draw)
		check(draw_index==replay.size() and target==before and queue==before_queue,"native random replay exhausts exact draws without mutating inputs")
		var wanted:Dictionary=row["native"]
		check(result["changes"]["status_counters"]["poison"]==int(wanted["poison"]) and result["changes"]["status_flags"]==int(wanted["status"]),"native poison duration/intensity/additive merge matches")
		check(result["changes"]["status_counters"]["paralysis"]==2 and result["changes"]["status_counters"]["no_magic"]==3,"weapon poison preserves other native conditions")
		for index in range(queue["slots"].size()):check(result["queue"]["slots"][index]["enabled"]==bool(wanted["queue"][index]),"exact future queue eligibility agrees with original")
	for row in packet["queue"]:
		var c:Dictionary=row["input"];var queue:={"index":int(c["index"]),"round":2,"slots":[]}
		for slot in c["slots"]:queue["slots"].append({"id":str(int(slot[0])),"enabled":bool(slot[1])})
		var result:=BattlePlayLoop.CoreTurnQueue.cancel_pending(queue,"1")
		check(result["ok"] and result["index"]==int(row["native"]["cancelled_index"]),"native first future eligible slot only, including past/disabled/duplicate pointers")
	for row in packet["gear"]:
		var loop:=original.duplicate(true);var actor:=BattlePlayLoop.unit_ref(loop,"leonard")
		actor["equipment"]=[]
		for code in row["input"]["codes"]:actor["equipment"].append({"item_code":int(code)})
		var source:=WeaponEffectRules.effects(actor,loop["equipment_items"])
		var protection:=BattlePlayLoop.StatusApplicationRules.equipment_modifiers(actor,loop["equipment_items"])
		for native in row["native"]:check((int(source["flags"]) | int(protection["effects"]))==int(native["values"]["effects"]),"original full refresh agrees with OR of current slots")


func series_transactions() -> void:
	check(WeaponEffectRules.feedback({"poison":{"applied":true,"before_word":0x140009,"after_word":0x180009}})=="毒效增強","duration-capped poison reports actual intensity growth")
	check(WeaponEffectRules.feedback({"poison":{"applied":true,"before_word":0x320009,"after_word":0x320009}})=="中毒維持","fully capped poison never invents an extra duration")
	var loop:=fixture(35,true,true)
	own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
	var before:=loop.duplicate(true)
	var result:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(loop,"attack"),Vector2i(8,6),zero)
	var strike:Dictionary=result["last_attack"]
	check(loop==before and strike["followups"].size()==1 and not strike["counter"].is_empty(),"two main strikes plus real counter remain a single transaction")
	check(not strike.has("weapon_effects") and strike["followups"][0]["weapon_effects"]["poison"]["applied"],"only final extra strike samples and applies poison")
	check(strike["defender_before"]["status_counters"]["poison"]==0 and strike["defender_after"]["status_counters"]["poison"]==0,"first strike cannot display future series poison")
	check(strike["counter"]["attacker_before"]["status_counters"]["poison"]>0,"counter starts with actually applied preceding poison")
	var basis:=int(strike["experience_basis"]["points"])+int(strike["followups"][0]["experience_basis"]["points"])
	check(strike["experience_settlement"]["base"]==basis and int(strike["followups"][0]["native_contribution"])==int(strike["followups"][0]["actual_damage"]),"weapon affliction adds no spell contribution or duplicated EXP")
	result=BattlePlayLoop.finish_exhausted_action(result)
	var second:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(result,"attack"),Vector2i(8,6),zero)
	second=BattlePlayLoop.finish_exhausted_action(second)
	check(second["extra_action"]["pending"]==false and int(BattlePlayLoop.unit(second,"enemy021_1")["status_counters"]["poison"])&0xffff==2,"fresh independent second action may apply its own one-turn poison increment")
	var miss:=fixture()
	var actor:=BattlePlayLoop.unit_ref(miss,"leonard");var victim:=BattlePlayLoop.unit_ref(miss,"enemy021_1")
	actor["hit_bonus_accum"]=0;actor["combat_profile"]["live_hit_ratio"]=0;victim["combat_profile"]["avoid_hit_ratio"]=100
	var missed:=BattleLoopCombat.apply_strike(miss,"leonard","enemy021_1",high,false,0)
	check(not missed["hit"] and not missed.has("weapon_effects") and victim["status_counters"]["poison"]==0,"final miss consumes no poison chance despite active weapon")
	var partial:=fixture()
	var first:=BattleLoopCombat.apply_strike(partial,"leonard","enemy021_1",zero,false,1)
	check(first["hit"] and not first.has("weapon_effects"),"intermediate hit only converts its own damage EXP")
	BattlePlayLoop.unit_ref(partial,"leonard")["hit_bonus_accum"]=0
	BattlePlayLoop.unit_ref(partial,"leonard")["combat_profile"]["live_hit_ratio"]=0
	BattlePlayLoop.unit_ref(partial,"enemy021_1")["combat_profile"]["avoid_hit_ratio"]=100
	var last:=BattleLoopCombat.apply_strike(partial,"leonard","enemy021_1",high,false,0)
	check(not last["hit"] and not last.has("weapon_effects") and not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(partial,"enemy021_1")),"last miss does not backfill poison from the previous hit")
	var lethal:=fixture();own(lethal, "skill_book")["actors"]["039"]["double_attack"]=true
	BattlePlayLoop.unit_ref(lethal,"enemy021_1")["hp"]=1
	var kill:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(lethal,"attack"),Vector2i(8,6),zero)
	check(kill["last_attack"]["followups"].is_empty() and kill["last_attack"]["weapon_effects"]["poison"]["applied"],"early lethal strike reaches original effect draws once and truncates followups")
	check(BattlePlayLoop.unit(kill,"enemy021_1")["status_flags"]==0 and WeaponEffectRules.feedback(kill["last_attack"]["weapon_effects"],false)=="","dead actor cleanup suppresses impossible persistent affliction feedback")


## 0x409310 status word: weaken 0x20000 / no-magic 0x80000 / paralysis 0x100000 / poison 0x200000 each roll
## rand(100)+1 <= 25 after the 0x40e2f0 immunity test; random_status_error 0x40000 replaces the word with one
## bit from rand(100)+1 (1..24 / 25..49 / 50..74 / 75..100). 209 詛咒戒指 and 71 朧月 carry the random bit,
## 51 attack_weaken, 66 attack_nomagic, 220 avoid_weaken.
func status_word() -> void:
	var base := fixture(35)
	var catalog: Dictionary = base["equipment_items"]
	check(int(catalog["209"]["weapon_effect_flags"]) == WeaponEffectRules.RANDOM and catalog["209"]["supported"] and int(catalog["71"]["weapon_effect_flags"]) == WeaponEffectRules.RANDOM and not catalog["71"]["supported"],"random_status_error maps to 0x40000; 71 stays unsupported for its range6CellShoot range only")
	check(int(catalog["51"]["weapon_effect_flags"]) == WeaponEffectRules.WEAKEN and int(catalog["66"]["weapon_effect_flags"]) == WeaponEffectRules.NO_MAGIC and int(catalog["220"]["status_effect_flags"]) == 0x2000000,"attack_weaken 0x20000 / attack_nomagic 0x80000 / avoid_weaken 0x2000000 follow the ITEM loader")
	var ring := base.duplicate(true)
	var actor := BattlePlayLoop.unit_ref(ring,"leonard")
	set_gear(actor,catalog,"weapon",0)
	set_gear(actor,catalog,"accessory1",209)
	var target := BattlePlayLoop.unit_ref(ring,"enemy021_1")
	var healthy_attack: int = target["combat_profile"]["live_attack_damage"]
	var healthy_max: int = target["max_hp"]
	var prepared := WeaponEffectRules.prepare(actor,target,ring["skill_book"],catalog,ring["turn_queue"])
	check(prepared["ok"] and int(prepared["flags"]) == WeaponEffectRules.RANDOM,"an accessory contributes its +0xa0 word like a weapon (0x448420 OR over every slot)")
	var expected := {23: "weaken", 24: "no_magic", 48: "no_magic", 49: "paralysis", 73: "paralysis", 74: "poison", 99: "poison", 0: "weaken"}
	for value in expected:
		replay = [{"bound":100,"value":value},{"bound":100,"value":25}];draw_index = 0
		var picked := WeaponEffectRules.resolve(prepared,native_draw)
		check(draw_index == 2 and picked["receipt"]["random_status"]["selected"] == expected[value] and int(picked["receipt"]["random_status"]["roll"]) == value + 1 and not picked["receipt"][expected[value]]["applied"] and picked["changes"]["status_flags"] == target["status_flags"],"rand(100)+1 = %d selects %s; the branch's own roll 26 leaves the target untouched" % [value + 1, expected[value]])
	# weaken: rand(2)+1 turns, 0x406fe0(3, 7) = 5 − rand(3) + rand(3), then 0x448840.
	replay = [{"bound":100,"value":0},{"bound":100,"value":24},{"bound":2,"value":1},{"bound":3,"value":0},{"bound":3,"value":2}];draw_index = 0
	var struck := target.duplicate(true);struck["hp"] = 4000
	var weakened := WeaponEffectRules.resolve(prepared,native_draw,0,struck)
	var word: int = weakened["changes"]["status_counters"]["weaken"]
	check(draw_index == 5 and weakened["receipt"]["weaken"]["applied"] and (word & 0xffff) == 2 and (word >> 16) == 7 and (weakened["changes"]["status_flags"] & BattlePlayLoop.StatusEffectRules.WEAKEN) != 0,"weaken applies 2 turns at power 7 on the 25th roll")
	check(weakened["receipt"]["weaken"]["refreshed"] and int(weakened["changes"]["combat_profile"]["live_attack_damage"]) < healthy_attack and int(weakened["changes"]["max_hp"]) < healthy_max and int(weakened["changes"]["hp"]) == mini(4000, int(weakened["changes"]["max_hp"])),"the 0x448840 refresh lowers the derived stats and clamps the struck HP, not the pre-strike snapshot")
	check(WeaponEffectRules.feedback(weakened["receipt"]) == "衰弱","weaken feedback names the affliction")
	check(target == BattlePlayLoop.unit(ring,"enemy021_1") and not BattlePlayLoop.StatusEffectRules.weakened(target),"resolve never mutates the prepared target")
	# no_magic / paralysis: rand(2)+1 turns, no power word.
	replay = [{"bound":100,"value":30},{"bound":100,"value":0},{"bound":2,"value":0}];draw_index = 0
	var silenced := WeaponEffectRules.resolve(prepared,native_draw)
	check(draw_index == 3 and silenced["receipt"]["no_magic"]["applied"] and silenced["changes"]["status_counters"]["no_magic"] == 1 and WeaponEffectRules.feedback(silenced["receipt"]) == "禁魔","no-magic adds one turn without an intensity draw")
	replay = [{"bound":100,"value":60},{"bound":100,"value":0},{"bound":2,"value":1}];draw_index = 0
	var stunned := WeaponEffectRules.resolve(prepared,native_draw)
	check(draw_index == 3 and stunned["receipt"]["paralysis"]["applied"] and stunned["changes"]["status_counters"]["paralysis"] == 2 and WeaponEffectRules.feedback(stunned["receipt"]) == "麻痺","paralysis adds rand(2)+1 turns")
	replay = [{"bound":100,"value":80},{"bound":100,"value":0},{"bound":2,"value":0},{"bound":9,"value":8},{"bound":9,"value":0}];draw_index = 0
	var poisoned := WeaponEffectRules.resolve(prepared,native_draw)
	check(draw_index == 5 and poisoned["receipt"]["poison"]["applied"] and int(poisoned["receipt"]["poison"]["sampled_power"]) == 16,"the random poison branch is the existing 0x4091b0 helper (16..32)")
	# random replaces the equipment word: a poison weapon plus the ring only runs the picked branch.
	var mixed := ring.duplicate(true)
	set_gear(BattlePlayLoop.unit_ref(mixed,"leonard"),catalog,"weapon",35)
	var mixed_prepared := WeaponEffectRules.prepare(BattlePlayLoop.unit_ref(mixed,"leonard"),BattlePlayLoop.unit_ref(mixed,"enemy021_1"),mixed["skill_book"],catalog,mixed["turn_queue"])
	replay = [{"bound":100,"value":0},{"bound":100,"value":0},{"bound":2,"value":0},{"bound":3,"value":1},{"bound":3,"value":1}];draw_index = 0
	var replaced := WeaponEffectRules.resolve(mixed_prepared,native_draw,0,BattlePlayLoop.unit(mixed,"enemy021_1"))
	check(int(mixed_prepared["flags"]) == (WeaponEffectRules.RANDOM | WeaponEffectRules.POISON) and draw_index == 5 and replaced["receipt"]["weaken"]["applied"] and replaced["receipt"]["poison"].is_empty(),"random_status_error overwrites the OR word (0x409310 uVar3), so attack_poison does not roll")
	# direct attack_weaken (51) rolls the weaken branch without the random pick.
	var thrust := base.duplicate(true)
	set_gear(BattlePlayLoop.unit_ref(thrust,"leonard"),catalog,"weapon",51)
	var thrust_prepared := WeaponEffectRules.prepare(BattlePlayLoop.unit_ref(thrust,"leonard"),BattlePlayLoop.unit_ref(thrust,"enemy021_1"),thrust["skill_book"],catalog,thrust["turn_queue"])
	replay = [{"bound":100,"value":24},{"bound":2,"value":0},{"bound":3,"value":2},{"bound":3,"value":0}];draw_index = 0
	var direct := WeaponEffectRules.resolve(thrust_prepared,native_draw,0,BattlePlayLoop.unit(thrust,"enemy021_1"))
	check(int(thrust_prepared["flags"]) == WeaponEffectRules.WEAKEN and draw_index == 4 and direct["receipt"]["weaken"]["applied"] and int(direct["receipt"]["weaken"]["sampled_power"]) == 3 and not direct["receipt"].has("random_status"),"51 attack_weaken rolls the weaken branch directly (power 5 − 2 + 0)")
	# immunity: 220 avoid_weaken skips the weaken roll; 229 keep_status_good (0x80) skips every branch.
	var guarded := ring.duplicate(true)
	var guard := BattlePlayLoop.unit_ref(guarded,"enemy021_1")
	guard["equipment"].append({"slot":"accessory1","item_code":220})
	var guarded_prepared := WeaponEffectRules.prepare(BattlePlayLoop.unit_ref(guarded,"leonard"),guard,guarded["skill_book"],catalog,guarded["turn_queue"])
	replay = [{"bound":100,"value":0}];draw_index = 0
	var shrugged := WeaponEffectRules.resolve(guarded_prepared,native_draw)
	check(draw_index == 1 and shrugged["receipt"]["weaken"]["immune"] and WeaponEffectRules.feedback(shrugged["receipt"]) == "衰弱免疫","avoid_weaken (0x2000000) answers the 0x40e2f0 test before any weaken roll")
	guard["equipment"][guard["equipment"].size() - 1] = {"slot":"accessory1","item_code":229}
	guarded_prepared = WeaponEffectRules.prepare(BattlePlayLoop.unit_ref(guarded,"leonard"),guard,guarded["skill_book"],catalog,guarded["turn_queue"])
	for value in [0, 30, 60, 80]:
		replay = [{"bound":100,"value":value}];draw_index = 0
		var kept := WeaponEffectRules.resolve(guarded_prepared,native_draw)
		check(draw_index == 1 and kept["receipt"][kept["receipt"]["random_status"]["selected"]]["immune"],"keep_status_good protects against the picked status: " + str(kept["receipt"]["random_status"]["selected"]))
	# play loop: the ring's final strike weakens the defender and refreshes it through the shared seam.
	var battle := ring.duplicate(true)
	var struck_before: Dictionary = BattlePlayLoop.unit(battle,"enemy021_1")
	var fought := BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(battle,"attack"),Vector2i(8,6),zero)
	var effects: Dictionary = fought["last_attack"]["weapon_effects"]
	var defender := BattlePlayLoop.unit(fought,"enemy021_1")
	check(effects["random_status"]["selected"] == "weaken" and effects["weaken"]["applied"] and BattlePlayLoop.StatusEffectRules.weakened(defender),"an all-zero stream picks weaken and applies it on the final strike")
	check(defender["hp"] == mini(struck_before["hp"] - int(fought["last_attack"]["actual_damage"]), int(defender["max_hp"])) and int(defender["combat_profile"]["live_attack_damage"]) < healthy_attack and defender["max_hp"] < healthy_max,"the defender keeps its struck HP (clamped to the refreshed weakened maximum, which replaces the fixture's inflated 5000) and stands on weakened derived stats")
	check(BattlePlayLoop.CoreCombatRules.input_error(defender) == "","the weakened defender remains a valid combat input")
	var encoded := BattleCheckpoint.encode(fought,{"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1})
	check(encoded["ok"] and BattleCheckpoint.decode(encoded["bytes"],fought)["snapshot"]["loop"] == fought,"the weakened state round-trips through the checkpoint")


func queue_lifecycle() -> void:
	var loop:=fixture(29,false,true)
	var target:=BattlePlayLoop.unit_ref(loop,"enemy021_1")
	set_gear(target,loop["equipment_items"],"accessory1",224)
	set_gear(target,loop["equipment_items"],"accessory2",227)
	target["hp"]=5000;target["max_hp"]=5000
	target["status_flags"]=3;target["status_counters"]={"poison":0x140003,"paralysis":0,"no_magic":2}
	var result:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(loop,"attack"),Vector2i(8,6),zero)
	check(result["last_attack"]["weapon_effects"]["cancel"]["cancelled"] and not result["last_attack"]["counter"].is_empty(),"cancelled future turn does not suppress current counter")
	result=BattlePlayLoop.finish_exhausted_action(result)
	check(not result["turn_queue"]["slots"][2]["enabled"] and result["selected_unit_id"]=="enemy023_1","cancelled actor slot persists beyond attack handoff")
	var saved:=BattleCheckpoint.encode(result,run_position_equipment_tests.VIEW);check(saved["ok"],"cancelled future slot is a valid save boundary")
	if saved["ok"]:
		var loaded:=BattleCheckpoint.decode(saved["bytes"], result)
		check(loaded["ok"] and loaded["snapshot"]["loop"]==result,"restore does not reenable cancelled slot or reapply poison/effects")
	var victim_before:=BattlePlayLoop.unit(result,"enemy021_1")
	var wrapped:=BattlePlayLoop.choose_command(result,"wait")
	check(wrapped["turn"]==2 and int(wrapped["action_end_sequence"])==int(result["action_end_sequence"])+1,"cancelled actor is omitted rather than receiving a status-skip tail")
	check(BattlePlayLoop.unit(wrapped,"enemy021_1")["status_counters"]==victim_before["status_counters"] and BattlePlayLoop.unit(wrapped,"enemy021_1")["mp"]==victim_before["mp"],"cancelled victim gets no poison tick, recovery, status decrement or extra action")
	check(wrapped["turn_queue"]["slots"].all(func(s):return s["enabled"]),"ordinary next-round rebuild restores cancelled eligibility")
	var current:=fixture(40,true,true)
	var foe:=BattlePlayLoop.unit_ref(current,"enemy021_1")
	# Counter fixture grants an existing same-source cancellation flag only; source
	# gear eligibility is checked separately, actor roles never rewrite native flags.
	own(current, "equipment_items")[str(int(foe["weapon_code"]))]["weapon_effect_flags"]=WeaponEffectRules.CANCEL
	var counter:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(current,"attack"),Vector2i(8,6),zero)
	check(counter["last_attack"]["counter"]["weapon_effects"]["cancel"]["triggered"] and not counter["last_attack"]["counter"]["weapon_effects"]["cancel"]["cancelled"],"counter cannot cancel the current attacker's already-active slot")
	counter=BattlePlayLoop.finish_exhausted_action(counter)
	check(counter["extra_action"]["pending"] and counter["selected_unit_id"]=="leonard","current owner's second independent action survives failed future-slot cancellation")


func gear_and_support() -> void:
	var loop:=fixture();var actor:=BattlePlayLoop.unit_ref(loop,"leonard")
	for code in [29,35,37]:
		var changed:=run_position_equipment_tests.equip(loop,"weapon",code)
		check(BattlePlayLoop.unit(changed,"leonard")["weapon_code"]==code,"live job94 can select native effect weapon "+str(code))
		var flags:int=WeaponEffectRules.effects(BattlePlayLoop.unit(changed,"leonard"),changed["equipment_items"])["flags"]
		check(flags==(WeaponEffectRules.CANCEL if code==29 else WeaponEffectRules.POISON),"changing weapon replaces current effect with no stale predecessor")
		var grown:=BattlePlayLoop.ProgressionRules.resolve_experience(BattlePlayLoop.unit(changed,"leonard"),200,changed["equipment_items"])
		check(WeaponEffectRules.effects(grown,changed["equipment_items"])["flags"]==flags,"level refresh retains only current source weapon capability")
	var protected:=run_position_equipment_tests.equip(loop,"accessory1",229)
	var target:=BattlePlayLoop.unit_ref(protected,"enemy021_1")
	target["equipment"].append({"slot":"accessory1","item_code":229})
	var proposal:=WeaponEffectRules.prepare(BattlePlayLoop.unit(protected,"leonard"),target,protected["skill_book"],protected["equipment_items"],protected["turn_queue"])
	var immune:=WeaponEffectRules.resolve(proposal,no_rng)
	check(immune["receipt"]["poison"]["immune"] and not immune["receipt"]["poison"]["applied"],"universal protection avoids even the independent poison chance draw")
	proposal["flags"]=WeaponEffectRules.CANCEL | WeaponEffectRules.POISON
	var cancellation:=WeaponEffectRules.resolve(proposal,zero)
	check(cancellation["receipt"]["cancel"]["cancelled"] and cancellation["receipt"]["poison"]["immune"],"universal status protection does not prevent cancel action")
	var existing:=fixture();var victim:=BattlePlayLoop.unit_ref(existing,"leonard")
	victim.merge(BattlePlayLoop.StatusEffectRules.apply(victim,"poison",2,30)["changes"],true)
	var guard:=run_position_equipment_tests.equip(existing,"accessory1",229)
	check(BattlePlayLoop.unit(guard,"leonard")["status_counters"]==victim["status_counters"],"equipping protection never cures existing poison")
	var cure:=BattlePlayLoop.use_item(guard,"246","leonard",BattlePlayLoop.unit(guard,"leonard")["inventory"].find(246))
	check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(cure,"leonard")),"same item cure removes weapon-compatible packed poison under protection")
	var ordinary:=run_position_equipment_tests.fixture("001")
	BattlePlayLoop.unit_ref(ordinary,"leonard")["inventory"]=[144,229,0,0,0,0,0,0]
	var armor:=run_position_equipment_tests.equip(ordinary,"armor",144)
	check(armor!=ordinary and BattlePlayLoop.StatusApplicationRules.modifiers(BattlePlayLoop.unit(armor,"leonard"),armor["skill_book"],armor["equipment_items"])["effects"]&0x80,"source sword job can equip universal-protection armor")
	var magic:=fixture()
	run_large_actor_tests.spell_kit(magic)
	var defended:=BattlePlayLoop.unit_ref(magic,"enemy021_1")
	defended["equipment"].append({"slot":"accessory1","item_code":229})
	var owner:=BattlePlayLoop.unit_ref(magic,"leonard")
	for id in magic["skill_book"]["skills"]:
		var entry:Dictionary=magic["skill_book"]["skills"][id]
		if entry["damage_policy"]!="native_magic_status":continue
		if not magic["skill_book"]["actors"]["039"]["supported_initial_ids"].has(id):own(magic, "skill_book")["actors"]["039"]["supported_initial_ids"].append(id)
		owner["mp"]=owner["max_mp"]
		var hit:=BattleLoopCombat.resolve_skill(magic,"leonard","enemy021_1",id,BattlePlayLoop.skill_fields(magic,id),owner["coord"],zero)
		check(not hit.is_empty() and defended["status_flags"]==0,"universal gear protects current status magic without bypassing its paid transaction: "+id)


func phase_cancellation() -> void:
	for code in [29,35]:
		var loop:=fixture(code,true);run_large_actor_tests.spell_kit(loop)
		var actor:=BattlePlayLoop.unit_ref(loop,"leonard")
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		var before:=loop.duplicate(true)
		var moved:=BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop,"move"),Vector2i(5,6))
		check(moved["pending_move"],"equipped large actor accepts a pending walk")
		var cancelled:=BattlePlayLoop.cancel_interaction(BattlePlayLoop.choose_command(moved,"attack"))
		check(cancelled==moved and cancelled["units"]!=before["units"],"target cancellation keeps the actual pending destination without any new effect")
		var restored:=BattlePlayLoop.cancel_interaction(BattlePlayLoop.cancel_pending_move(cancelled))
		check(restored["units"]==before["units"] and restored["turn_queue"]==before["turn_queue"] and restored["action_end_sequence"]==0,"movement rollback preserves conditions, resources and queue eligibility")
		check(BattlePlayLoop.magic_options(restored,"leonard").all(func(o):return not o["quote"]["ok"]),"cancelled movement cannot lift silence")
		var first:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(restored,"attack"),Vector2i(8,6),zero)
		check(not first["extra_action"]["pending"] and first["attacked_this_action"],"second action stays closed until the committed strike is presented")
		first=BattlePlayLoop.finish_exhausted_action(first)
		check(first["extra_action"]["pending"],"weapon tail commits before the independent second action")
		var repeat_cancel:=BattlePlayLoop.cancel_interaction(BattlePlayLoop.choose_command(first,"attack"))
		check(repeat_cancel==first and BattleCheckpoint.encode(repeat_cancel,run_position_equipment_tests.VIEW)["ok"],"second-action cancellation and save do not reapply poison or cancelled slots")
		var exchanged:=run_position_equipment_tests.equip(first,"weapon",37 if code==29 else 29)
		var final:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(exchanged,"attack"),Vector2i(8,6),zero)
		final=BattlePlayLoop.finish_exhausted_action(final)
		check(final["last_attack"]["weapon_effects"]["flags"]==(WeaponEffectRules.POISON if code==29 else WeaponEffectRules.CANCEL) and not final["extra_action"]["pending"] and final["action_end_sequence"]==1,"accepted second action uses replacement source and closes exactly once")
	var spell:=fixture();run_large_actor_tests.spell_kit(spell)
	var resolved:=BattlePlayLoop.attack_target(run_position_equipment_tests.selected(spell),"enemy021_1",zero)
	check(not resolved["last_attack"].has("weapon_effects") and resolved["last_attack"]["skill_id"]==run_position_equipment_tests.WIND,"ordinary weapon poison never leaks into a spell transaction")
	var malformed:=fixture()
	own(malformed, "equipment_items")["29"]["weapon_effect_flags"]=1
	check(run_position_equipment_tests.equip(malformed,"weapon",29)==malformed,"replacement weapon source is validated before inventory or actor changes commit")


func native_draw(bound:int)->int:
	check(draw_index<replay.size(),"no extra native weapon draw")
	if draw_index>=replay.size():return 0
	var row:Dictionary=replay[draw_index];draw_index+=1
	check(bound==int(row["bound"]),"original weapon RNG bound order")
	return int(row["value"])
