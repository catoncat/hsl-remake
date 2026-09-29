extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const ItemResolutionRules = preload("res://game/sim/ItemResolutionRules.gd")
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
const MOON := "special:magicOTHER:magicCode06"


func _init() -> void:
	tag = "TACTICAL_ITEMS_TESTS"


static func initial() -> Dictionary:
	return BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/tactical_items_trial.json"))

static func fixture() -> Dictionary:
	var loop := run_support_magic_tests.stat_fixture()
	var actor := BattlePlayLoop.unit_ref(loop,"tina")
	actor["inventory"] = [262,262,263,247,250,248,0,0]
	actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
	actor["equipment"].append({"slot":"accessory2","item_code":227})
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["stamina"] = 0
	BattlePlayLoop.unit_ref(loop,"enemy026_1").merge({"mp":0,"no_attack":true,"inventory":[0,0,0,0,0,0,0,0]},true)
	return loop

static func cast(loop: Dictionary, id: String, target: String) -> Dictionary:
	return BattlePlayLoop.attack_target(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop,"magic"),id),target,func(_bound):return 0)

func run() -> void:
	check(initial()["scenario_ok"],"published tactical training initializes")
	if not initial()["scenario_ok"]: return
	native_items()
	independent_actions()
	magic_and_expiry()
	cure_weaken()

func native_items() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_tactical_items.json"))
	var ordinary := BattleFixture.loop()
	var priest := run_support_magic_tests.priest_initial()
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var source: Dictionary = priest if c["actor"] == "002" else ordinary
		var target: Dictionary = source["units"].filter(func(a):return a["actor_id"]==c["actor"])[0].duplicate(true)
		target.merge({"level":int(c["level"]),"hp":1,"mp":0,"stamina":int(c["stamina"]),"exp":37,"status_flags":0,"status_counters":{}},true)
		for key in c["words"]:
			target["status_counters"][key] = int(c["words"][key])
			if int(c["words"][key]) != 0: target["status_flags"] |= {"poison":1,"no_magic":2,"paralysis":4,"weaken":8,"attack_up":16,"defense_up":32}[key]
		target = BattlePlayLoop.ProgressionRules.refresh_growth_stats(target,source["equipment_items"])
		var before := target.duplicate(true)
		if c["outside_battle"]:
			continue
		var item: Dictionary = source["consumables"][str(int(c["code"]))]
		var quote := ItemUseRules.prepare(target,item)
		check(target == before,"native-comparison preview never mutates its actor")
		if quote["ok"]:
			target.merge(quote["changes"],true)
			var cursor := 0
			for proposal in quote["stat_proposals"]:
				var power := int(proposal["before_word"]) >> 16
				if proposal["roll_required"]:
					check(int(row["draws"][cursor]["bound"]) == int(proposal["high"])-int(proposal["low"])+1,"native item uses one inclusive5..10 draw")
					power = int(proposal["low"])+int(row["draws"][cursor]["value"]);cursor+=1
				target["status_counters"][proposal["kind"]] = StatEnhancementRules.item_word(int(proposal["before_word"]),power)
				target["status_flags"] |= int(StatEnhancementRules.FLAGS[proposal["kind"]])
			check(cursor == row["draws"].size(),"existing positive state extends with no additional random draw")
		else: check(quote["reason"] == "item_has_no_effect" and row["draws"].is_empty(),"already full state uses explicit no-consumption remake policy")
		target = BattlePlayLoop.ProgressionRules.refresh_growth_stats(target,source["equipment_items"])
		for key in row["native"]["words"]: check(StatEnhancementRules.word(target,key) == int(row["native"]["words"][key]),"original item preserves/updates packed "+key)
		for key in ["hp","mp","stamina","exp"]:check(int(target[key]) == int(row["native"][key]),"original tactical item "+key)
		check(int(target["status_flags"]) == int(row["native"]["flags"]),"original selected clear/enable flags match")
		for pair in [["attack","live_attack_damage"],["defense","live_defense"]]: check(target["combat_profile"][pair[1]] == int(row["derived"][pair[0]]),"item derived current "+pair[0])
	for row in packet["scans"]:
		var scanned := ItemUseRules.first_status_slot(row["input"]["inventory"],ordinary["consumables"],int(row["input"]["flags"]))
		check(scanned["ok"] and scanned["index"] + 1 == int(row["native"]),"first matching native cure slot includes silence and keeps source ordering")

func independent_actions() -> void:
	var loop := fixture();var target := BattlePlayLoop.unit_ref(loop,"tina")
	run_support_magic_tests.buff(loop,"tina","attack_up",4,24);run_support_magic_tests.buff(loop,"tina","defense_up",4,30)
	for key in ["poison","no_magic"]: target.merge(BattlePlayLoop.StatusEffectRules.apply(target,key,3,5 if key == "poison" else 0)["changes"],true)
	BattlePlayLoop.unit_ref(loop,"companion")["hp"] = 1
	var cured := BattlePlayLoop.use_item(loop,"247")
	check(not BattlePlayLoop.StatusEffectRules.magic_blocked(BattlePlayLoop.unit(cured,"tina")) and BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(cured,"tina")),"self破魔咒 removes silence only")
	check(StatEnhancementRules.word(BattlePlayLoop.unit(cured,"tina"),"attack_up") == StatEnhancementRules.word(target,"attack_up") and cured["action_end_sequence"] == 0,"first cure does not prematurely expire existing positive states")
	var healed := cast(cured,run_support_magic_tests.HEAL,"companion")
	healed = BattlePlayLoop.finish_exhausted_action(healed)
	check(healed["last_attack"].get("healing",0) > 0 and healed["action_end_sequence"] == 1 and BattlePlayLoop.unit(healed,"tina")["mp"] == target["mp"]-6,"second action can pay actual healing after silence removal and ticks once")
	var drink := fixture();BattlePlayLoop.unit_ref(drink,"enemy026_1")["coord"] = Vector2i(15,16)
	drink = BattlePlayLoop.use_item(drink,"250")
	check(BattlePlayLoop.unit(drink,"tina")["stamina"] == 20 and drink["last_item_use"]["restored_stamina"] == 20,"神威之酒 makes the owned20ST special payable")
	drink = BattlePlayLoop.attack_target(BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(drink,"special"),MOON),"enemy026_1",func(_n):return 0,BattlePlayLoop.unit(drink,"tina")["coord"])
	drink = BattlePlayLoop.finish_exhausted_action(drink)
	check(drink["last_attack"].get("skill_id") == MOON and BattlePlayLoop.unit(drink,"tina")["stamina"] == 0 and drink["action_end_sequence"] == 1,"actual Moon Dance pays once after the first-action drink")
	var partial := fixture();BattlePlayLoop.unit_ref(partial,"tina")["stamina"] = 59
	partial = BattlePlayLoop.use_item(partial,"250")
	check(partial["last_item_use"]["restored_stamina"] == 1 and BattlePlayLoop.unit(partial,"tina")["stamina"] == 60,"last point caps at60 with correct receipt")
	var move := fixture();move = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(move,"move"),Vector2i(15,16))
	check(move["moved_this_action"],"item user can first use a real movement budget")
	move = BattlePlayLoop.use_item(move,"263")
	check(move["extra_action"]["pending"] and not move["moved_this_action"] and BattlePlayLoop.command_available(move,"magic"),"item completes moved action and fresh second action regains stationary casting")

## ITEM cure_weaken (loader 0x447fe2 -> item+0xa0 0x10000000; 0x40a31f clears +0x38 / flag 8, 0x40a337 refreshes):
## 249 振奃劑 cures only 衰弱, 251 聖潔香水 cures all four, and 0x40c230 scans by the same bit.
func cure_weaken() -> void:
	var healthy := fixture()
	var healthy_attack: int = BattlePlayLoop.unit(healthy,"tina")["combat_profile"]["live_attack_damage"]
	var weak := fixture();var tina := BattlePlayLoop.unit_ref(weak,"tina")
	tina["inventory"] = [249,251,247,0,0,0,0,0]
	tina.merge(BattlePlayLoop.StatusEffectRules.apply_weaken(tina,3,10)["changes"],true)
	tina.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(tina,weak["equipment_items"]),true)
	check(BattlePlayLoop.StatusEffectRules.weakened(tina) and tina["combat_profile"]["live_attack_damage"] < healthy_attack,"an active 衰弱 lowers the derived attack before the cure")
	var quote := ItemUseRules.prepare(tina,weak["consumables"]["249"])
	check(quote["ok"] and quote["cured_weaken"] and not quote["cured_poison"] and quote["stat_proposals"].is_empty(),"振奮劑 preview reports the weaken cure only")
	var cured := BattlePlayLoop.use_item(weak,"249")
	var after := BattlePlayLoop.unit(cured,"tina")
	check(cured["last_item_use"]["cured_weaken"] and cured["last_item_use"]["draws"].is_empty() and no_draw(cured, weak, "damage"),"振奃劑 commits a weaken cure receipt without a random draw")
	check(not BattlePlayLoop.StatusEffectRules.weakened(after) and not after["status_counters"].has("weaken") and after["inventory"] == [251,247,0,0,0,0,0,0],"the cure clears flag 8 and the +0x38 word and removes one 249")
	check(after["combat_profile"]["live_attack_damage"] == healthy_attack,"the cure block refresh (0x448840) restores the unweakened derived attack")
	var lapse := fixture();var fading := BattlePlayLoop.unit_ref(lapse,"tina")
	fading.merge(BattlePlayLoop.StatusEffectRules.apply_weaken(fading,2,10)["changes"],true)
	fading.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(fading,lapse["equipment_items"]),true)
	for _n in range(30):
		if not BattlePlayLoop.StatusEffectRules.weakened(BattlePlayLoop.unit(lapse,"tina")): break
		if lapse["interaction"] == "ai_resolving": lapse = BattlePlayLoop.step_ai_turn(lapse,func(_bound):return 0)
		else: lapse = BattlePlayLoop.choose_command(lapse,"wait")
	check(lapse["last_action_end"]["expired"].has("weaken") and BattlePlayLoop.unit(lapse,"tina")["combat_profile"]["live_attack_damage"] == healthy_attack,"衰弱 expiring at action end refreshes (0x40b910 -> 0x448840) back to the unweakened derived attack")
	# Product self-heal (ProgressionRules.self_heal, HSL_SELF_HEAL): a drifted derived attack
	# is refreshed and the command runs as on the consistent unit, with one HSL_SELF_HEAL log
	# line; strict mode still rejects it.
	var drift := fixture();var drifted := BattlePlayLoop.unit_ref(drift,"tina")
	drifted.merge(BattlePlayLoop.StatusEffectRules.apply_weaken(drifted,3,10)["changes"],true)
	drifted.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(drifted,drift["equipment_items"]),true)
	var consistent := BattlePlayLoop.copy(drift);var waited := BattlePlayLoop.choose_command(consistent,"wait")
	drifted["combat_profile"]["live_attack_damage"] += 7
	var strict := BattlePlayLoop.choose_command(drift,"wait")
	check(not BattlePlayLoop.same_state(waited,consistent) and BattlePlayLoop.same_state(strict,drift),"strict mode still rejects every command of a unit whose derived attack drifted")
	var sink := HealLog.new();OS.add_logger(sink)
	BattlePlayLoop.ProgressionRules.self_heal = true
	var healed := BattlePlayLoop.choose_command(drift,"wait")
	BattlePlayLoop.ProgressionRules.self_heal = false
	OS.remove_logger(sink)
	var lines := sink.lines.filter(func(l):return l.begins_with("HSL_SELF_HEAL "))
	check(BattlePlayLoop.same_state(healed,waited),"self-heal refreshes the drifted derived attack (0x448840) and the wait command runs as on the consistent unit")
	check(lines.size() == 1 and lines[0].strip_edges() == "HSL_SELF_HEAL unit=tina level=0 round=1 reason=inconsistent_enhanced_live_attack_damage","self-heal logs one HSL_SELF_HEAL line: %s" % str(lines))
	var none := fixture();BattlePlayLoop.unit_ref(none,"tina")["inventory"] = [249,0,0,0,0,0,0,0]
	var wasted := BattlePlayLoop.use_item(none,"249")
	check(wasted["item_use_sequence"] == 1 and BattlePlayLoop.unit(wasted,"tina")["inventory"] == [0,0,0,0,0,0,0,0] and not wasted["last_item_use"]["cured_weaken"],"振奃劑 on a healthy target still spends the 249 (0x444aba)")
	var poisoned := fixture();var both := BattlePlayLoop.unit_ref(poisoned,"tina")
	both["inventory"] = [251,0,0,0,0,0,0,0]
	both.merge(BattlePlayLoop.StatusEffectRules.apply_weaken(both,2,5)["changes"],true)
	both.merge(BattlePlayLoop.StatusEffectRules.apply(both,"poison",3,5)["changes"],true)
	both.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(both,poisoned["equipment_items"]),true)
	var perfume := BattlePlayLoop.use_item(poisoned,"251")
	var clean := BattlePlayLoop.unit(perfume,"tina")
	check(perfume["last_item_use"]["cured_weaken"] and perfume["last_item_use"]["cured_poison"] and clean["status_flags"] == 0 and clean["combat_profile"]["live_attack_damage"] == healthy_attack,"聖潔香水 cures 衰弱 and poison in one use")
	var scan := ItemUseRules.first_status_slot([247,248,249,251,0,0,0,0],weak["consumables"],BattlePlayLoop.StatusEffectRules.WEAKEN)
	check(scan["ok"] and scan["index"] == 2,"0x40c230 picks the first cure_weaken item for negative mask 8")
	scan = ItemUseRules.first_status_slot([249,0,0,0,0,0,0,0],weak["consumables"],BattlePlayLoop.StatusEffectRules.POISON)
	check(scan["ok"] and scan["index"] == -1,"a weaken-only cure is not a poison cure")


func magic_and_expiry() -> void:
	var base := fixture()
	var item := BattlePlayLoop.use_item(base,"262")
	var low := StatEnhancementRules.power(BattlePlayLoop.unit(item,"tina"),"attack_up")
	var raised := cast(item,run_support_magic_tests.ATT,"tina")
	check(raised["scenario_ok"] and StatEnhancementRules.power(BattlePlayLoop.unit(raised,"tina"),"attack_up") >= low and raised["last_attack"].get("stat_effects",[]).size() == 1,"magic accepts the smaller source-item strength and uses its own merge")
	var stronger := fixture();run_support_magic_tests.buff(stronger,"tina","attack_up",4,70)
	var extended := BattlePlayLoop.use_item(stronger,"262")
	check(StatEnhancementRules.power(BattlePlayLoop.unit(extended,"tina"),"attack_up") == 70 and extended["last_item_use"]["draws"].is_empty() and (StatEnhancementRules.word(BattlePlayLoop.unit(extended,"tina"),"attack_up") & 65535) == 7,"item after stronger magic preserves all its original power and extends only time")
	var defensive := BattlePlayLoop.use_item(fixture(),"263","companion")
	var ally := BattlePlayLoop.unit(defensive,"companion")
	check(StatEnhancementRules.power(ally,"defense_up") in range(5,11) and (StatEnhancementRules.word(ally,"defense_up") & 65535) == 3,"adjacent recipient gains exactly one source item enhancement")
	var growth := BattlePlayLoop.ProgressionRules.resolve_experience(ally,100,defensive["equipment_items"])
	check(StatEnhancementRules.word(growth,"defense_up") == StatEnhancementRules.word(ally,"defense_up") and BattlePlayLoop.ProgressionRules.enhancement_profile_error(growth,defensive["equipment_items"]) == "","level refresh keeps low-strength item enhancements exactly once")
	var dispelled := cast(defensive,run_support_magic_tests.DISPEL,"enemy026_1")
	check(dispelled["units"] == defensive["units"] and no_draw(dispelled, defensive, "damage"),"unbuffed enemy cannot consume a false dispel or draw from the damage stream")
	var cursor := BattlePlayLoop.use_item(fixture(),"263")
	var saved_word := StatEnhancementRules.word(BattlePlayLoop.unit(cursor,"tina"),"defense_up")
	for _n in range(30):
		if StatEnhancementRules.word(BattlePlayLoop.unit(cursor,"tina"),"defense_up") == 0: break
		if cursor["interaction"] == "ai_resolving": cursor = BattlePlayLoop.step_ai_turn(cursor,func(_bound):return 0)
		else: cursor = BattlePlayLoop.choose_command(cursor,"wait")
	check(saved_word != 0 and StatEnhancementRules.word(BattlePlayLoop.unit(cursor,"tina"),"defense_up") == 0 and cursor["last_action_end"]["expired"].has("defense_up"),"actual independent actions and queue cycles expire the local enhancement")
	check(BattlePlayLoop.unit(cursor,"tina")["combat_profile"]["live_defense"] == BattlePlayLoop.unit(base,"tina")["combat_profile"]["live_defense"],"item expiry restores exact base/equipment defense")


## Collects printed lines while a check reads the game log (Godot Logger).
class HealLog extends Logger:
	var lines: Array = []
	func _log_message(message: String, _error: bool) -> void:
		lines.append(message)
