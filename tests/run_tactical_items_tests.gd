extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")
const Cases = preload("res://tests/run_support_magic_tests.gd")
const Priest = preload("res://tests/run_support_magic_tests.gd")
const Items = preload("res://game/sim/ItemUseRules.gd")
const Resolve = preload("res://game/sim/ItemResolutionRules.gd")
const Stats = preload("res://game/sim/StatEnhancementRules.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
const MOON := "special:magicOTHER:magicCode06"


func _init() -> void:
	tag = "TACTICAL_ITEMS_TESTS"


static func initial() -> Dictionary:
	return Loop.create([],"",Loop.BattleScenario.load_file("res://content/battles/tactical_items_trial.json"))

static func fixture() -> Dictionary:
	var loop := Cases.stat_fixture()
	var actor := Loop._unit(loop,"tina")
	actor["inventory"] = [262,262,263,247,250,248,0,0]
	actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
	actor["equipment"].append({"slot":"accessory2","item_code":227})
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["stamina"] = 0
	Loop._unit(loop,"enemy026_1").merge({"mp":0,"no_attack":true,"inventory":[0,0,0,0,0,0,0,0]},true)
	return loop

static func cast(loop: Dictionary, id: String, target: String) -> Dictionary:
	return Loop.attack_target(Loop.choose_magic(Loop.choose_command(loop,"magic"),id),target,func(_bound):return 0)

func run() -> void:
	check(initial()["scenario_ok"],"published tactical training initializes")
	if not initial()["scenario_ok"]: return
	native_items()
	atomic_effects()
	independent_actions()
	magic_and_expiry()
	cure_weaken()
	ai_and_saves()
	terminal_guards()

func native_items() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_tactical_items.json"))
	var ordinary := BattleFixture.loop()
	var priest := Priest.priest_initial()
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var source: Dictionary = priest if c["actor"] == "002" else ordinary
		var target: Dictionary = source["units"].filter(func(a):return a["actor_id"]==c["actor"])[0].duplicate(true)
		target.merge({"level":int(c["level"]),"hp":1,"mp":0,"stamina":int(c["stamina"]),"exp":37,"status_flags":0,"status_counters":{}},true)
		for key in c["words"]:
			target["status_counters"][key] = int(c["words"][key])
			if int(c["words"][key]) != 0: target["status_flags"] |= {"poison":1,"no_magic":2,"paralysis":4,"weaken":8,"attack_up":16,"defense_up":32}[key]
		target = Loop.ProgressionRules.refresh_growth_stats(target,source["equipment_items"])
		var before := target.duplicate(true)
		if c["outside_battle"]:
			check(row["native"]["words"] == c["words"],"native outside-battle exclusion is retained as evidence, not a new remake surface")
			continue
		var item: Dictionary = source["consumables"][str(int(c["code"]))]
		var quote := Items.prepare(target,item)
		check(target == before,"native-comparison preview never mutates its actor")
		if quote["ok"]:
			target.merge(quote["changes"],true)
			var cursor := 0
			for proposal in quote["stat_proposals"]:
				var power := int(proposal["before_word"]) >> 16
				if proposal["roll_required"]:
					check(int(row["draws"][cursor]["bound"]) == int(proposal["high"])-int(proposal["low"])+1,"native item uses one inclusive5..10 draw")
					power = int(proposal["low"])+int(row["draws"][cursor]["value"]);cursor+=1
				target["status_counters"][proposal["kind"]] = Stats.item_word(int(proposal["before_word"]),power)
				target["status_flags"] |= int(Stats.FLAGS[proposal["kind"]])
			check(cursor == row["draws"].size(),"existing positive state extends with no additional random draw")
		else: check(quote["reason"] == "item_has_no_effect" and row["draws"].is_empty(),"already full state uses explicit no-consumption remake policy")
		target = Loop.ProgressionRules.refresh_growth_stats(target,source["equipment_items"])
		for key in row["native"]["words"]: check(Stats.word(target,key) == int(row["native"]["words"][key]),"original item preserves/updates packed "+key)
		for key in ["hp","mp","stamina","exp"]:check(int(target[key]) == int(row["native"][key]),"original tactical item "+key)
		check(int(target["status_flags"]) == int(row["native"]["flags"]),"original selected clear/enable flags match")
		for pair in [["attack","live_attack_damage"],["defense","live_defense"]]: check(target["combat_profile"][pair[1]] == int(row["derived"][pair[0]]),"item derived current "+pair[0])
	for row in packet["scans"]:
		var scanned := Items.first_status_slot(row["input"]["inventory"],ordinary["consumables"],int(row["input"]["flags"]))
		check(scanned["ok"] and scanned["index"] + 1 == int(row["native"]),"first matching native cure slot includes silence and keeps source ordering")

func atomic_effects() -> void:
	var loop := fixture();var before := loop.duplicate(true)
	var actor := Loop.unit(loop,"tina")
	for _i in range(5): check(Items.prepare(actor,loop["consumables"]["262"])["ok"],"first-use preview is useful without sampling")
	check(loop == before,"multiple previews preserve entire loop and independent random streams")
	var used := Loop.use_item(loop,"262")
	check(used["extra_action"]["pending"] and used["item_use_sequence"] == 1,"a confirmed inventory use commits one independent action")
	var receipt: Dictionary = used["last_item_use"]
	check(receipt["draws"].size() == 1 and int(receipt["draws"][0]["bound"]) == 6 and stream_of(used, "damage") == DamageRandom.rand(stream_of(loop, "damage"),6)["state"],"first temporary item commits one rand(6) from the loop's saved damage stream (0x409e10)")
	check(no_draw(used, loop, "reward"),"item draws never touch the reward stream")
	check(Loop.unit(used,"tina")["inventory"].count(262) == 1 and Stats.power(Loop.unit(used,"tina"),"attack_up") in range(5,11),"exactly one source item removed and actual5..10 power applied")
	check(Loop.unit(used,"tina")["exp"] == actor["exp"],"item strengthening does not fabricate magic contribution EXP")
	var repeated := Loop.use_item(used,"262")
	check(repeated["last_item_use"]["stat_effects"][0]["duration"] == 6 and repeated["last_item_use"]["draws"].is_empty() and no_draw(repeated, used, "damage"),"repeat extends three turns without changing strength or drawing")
	check(Stats.power(Loop.unit(repeated,"tina"),"attack_up") == Stats.power(Loop.unit(used,"tina"),"attack_up") and (Stats.word(Loop.unit(repeated,"tina"),"attack_up") & 65535) == 5,"second independent action ticks only once after the item extension")
	for code in ["247","250","262"]:
		var full := fixture();var target := Loop._unit(full,"tina")
		if code == "250": target["stamina"] = 60
		if code == "262": Cases.buff(full,"tina","attack_up",9,24)
		var spent := Loop.use_item(full,code)
		var holder := Loop.unit(spent,"tina")
		check(spent["item_use_sequence"] == 1 and holder["inventory"].count(int(code)) == target["inventory"].count(int(code))-1 and spent["last_item_use"]["draws"].is_empty() and no_draw(spent, full, "damage") and holder["hp"] == target["hp"] and holder["stamina"] == target["stamina"],"a use without effect still spends one item without drawing (0x444aba): "+code)
	var distant := fixture();Loop._unit(distant,"companion")["coord"] = Vector2i(20,20)
	check(Loop.use_item(distant,"263","companion") == distant,"unreachable recipient cannot consume a random item")
	var malformed := fixture();own(malformed, "consumables")["262"]["local_attack"] = [10,5]
	check(Loop.use_item(malformed,"262") == malformed,"invalid item range is rejected before inventory/random mutation")
	var unavailable := fixture();Loop._unit(unavailable,"tina").merge(Loop.StatusEffectRules.apply(Loop.unit(unavailable,"tina"),"paralysis",2)["changes"],true)
	check(Loop.use_item(unavailable,"262") == unavailable,"paralyzed owner cannot drink a tactical item")

func independent_actions() -> void:
	var loop := fixture();var target := Loop._unit(loop,"tina")
	Cases.buff(loop,"tina","attack_up",4,24);Cases.buff(loop,"tina","defense_up",4,30)
	for key in ["poison","no_magic"]: target.merge(Loop.StatusEffectRules.apply(target,key,3,5 if key == "poison" else 0)["changes"],true)
	Loop._unit(loop,"companion")["hp"] = 1
	var cured := Loop.use_item(loop,"247")
	check(not Loop.StatusEffectRules.magic_blocked(Loop.unit(cured,"tina")) and Loop.StatusEffectRules.poisoned(Loop.unit(cured,"tina")),"self破魔咒 removes silence only")
	check(Stats.word(Loop.unit(cured,"tina"),"attack_up") == Stats.word(target,"attack_up") and cured["action_end_sequence"] == 0,"first cure does not prematurely expire existing positive states")
	var healed := cast(cured,Priest.HEAL,"companion")
	healed = Loop.finish_exhausted_action(healed)
	check(healed["last_attack"].get("healing",0) > 0 and healed["action_end_sequence"] == 1 and Loop.unit(healed,"tina")["mp"] == target["mp"]-6,"second action can pay actual healing after silence removal and ticks once")
	var drink := fixture();Loop._unit(drink,"enemy026_1")["coord"] = Vector2i(15,16)
	drink = Loop.use_item(drink,"250")
	check(Loop.unit(drink,"tina")["stamina"] == 20 and drink["last_item_use"]["restored_stamina"] == 20,"神威之酒 makes the owned20ST special payable")
	drink = Loop.attack_target(Loop.choose_special(Loop.choose_command(drink,"special"),MOON),"enemy026_1",func(_n):return 0,Loop.unit(drink,"tina")["coord"])
	drink = Loop.finish_exhausted_action(drink)
	check(drink["last_attack"].get("skill_id") == MOON and Loop.unit(drink,"tina")["stamina"] == 0 and drink["action_end_sequence"] == 1,"actual Moon Dance pays once after the first-action drink")
	var partial := fixture();Loop._unit(partial,"tina")["stamina"] = 59
	partial = Loop.use_item(partial,"250")
	check(partial["last_item_use"]["restored_stamina"] == 1 and Loop.unit(partial,"tina")["stamina"] == 60,"last point caps at60 with correct receipt")
	var move := fixture();move = Loop.move_unit_to(Loop.choose_command(move,"move"),Vector2i(15,16))
	check(move["moved_this_action"],"item user can first use a real movement budget")
	move = Loop.use_item(move,"263")
	check(move["extra_action"]["pending"] and not move["moved_this_action"] and Loop.command_available(move,"magic"),"item completes moved action and fresh second action regains stationary casting")

## ITEM cure_weaken (loader 0x447fe2 -> item+0xa0 0x10000000; 0x40a31f clears +0x38 / flag 8, 0x40a337 refreshes):
## 249 振奃劑 cures only 衰弱, 251 聖潔香水 cures all four, and 0x40c230 scans by the same bit.
func cure_weaken() -> void:
	var healthy := fixture()
	var healthy_attack: int = Loop.unit(healthy,"tina")["combat_profile"]["live_attack_damage"]
	var weak := fixture();var tina := Loop._unit(weak,"tina")
	tina["inventory"] = [249,251,247,0,0,0,0,0]
	tina.merge(Loop.StatusEffectRules.apply_weaken(tina,3,10)["changes"],true)
	tina.merge(Loop.ProgressionRules.refresh_growth_stats(tina,weak["equipment_items"]),true)
	check(Loop.StatusEffectRules.weakened(tina) and tina["combat_profile"]["live_attack_damage"] < healthy_attack,"an active 衰弱 lowers the derived attack before the cure")
	var quote := Items.prepare(tina,weak["consumables"]["249"])
	check(quote["ok"] and quote["cured_weaken"] and not quote["cured_poison"] and quote["stat_proposals"].is_empty(),"振奮劑 preview reports the weaken cure only")
	var cured := Loop.use_item(weak,"249")
	var after := Loop.unit(cured,"tina")
	check(cured["last_item_use"]["cured_weaken"] and cured["last_item_use"]["draws"].is_empty() and no_draw(cured, weak, "damage"),"振奃劑 commits a weaken cure receipt without a random draw")
	check(not Loop.StatusEffectRules.weakened(after) and not after["status_counters"].has("weaken") and after["inventory"] == [251,247,0,0,0,0,0,0],"the cure clears flag 8 and the +0x38 word and removes one 249")
	check(after["combat_profile"]["live_attack_damage"] == healthy_attack,"the cure block refresh (0x448840) restores the unweakened derived attack")
	var none := fixture();Loop._unit(none,"tina")["inventory"] = [249,0,0,0,0,0,0,0]
	var wasted := Loop.use_item(none,"249")
	check(wasted["item_use_sequence"] == 1 and Loop.unit(wasted,"tina")["inventory"] == [0,0,0,0,0,0,0,0] and not wasted["last_item_use"]["cured_weaken"],"振奃劑 on a healthy target still spends the 249 (0x444aba)")
	var poisoned := fixture();var both := Loop._unit(poisoned,"tina")
	both["inventory"] = [251,0,0,0,0,0,0,0]
	both.merge(Loop.StatusEffectRules.apply_weaken(both,2,5)["changes"],true)
	both.merge(Loop.StatusEffectRules.apply(both,"poison",3,5)["changes"],true)
	both.merge(Loop.ProgressionRules.refresh_growth_stats(both,poisoned["equipment_items"]),true)
	var perfume := Loop.use_item(poisoned,"251")
	var clean := Loop.unit(perfume,"tina")
	check(perfume["last_item_use"]["cured_weaken"] and perfume["last_item_use"]["cured_poison"] and clean["status_flags"] == 0 and clean["combat_profile"]["live_attack_damage"] == healthy_attack,"聖潔香水 cures 衰弱 and poison in one use")
	var scan := Items.first_status_slot([247,248,249,251,0,0,0,0],weak["consumables"],Loop.StatusEffectRules.WEAKEN)
	check(scan["ok"] and scan["index"] == 2,"0x40c230 picks the first cure_weaken item for negative mask 8")
	scan = Items.first_status_slot([249,0,0,0,0,0,0,0],weak["consumables"],Loop.StatusEffectRules.POISON)
	check(scan["ok"] and scan["index"] == -1,"a weaken-only cure is not a poison cure")


func magic_and_expiry() -> void:
	var base := fixture()
	var item := Loop.use_item(base,"262")
	var low := Stats.power(Loop.unit(item,"tina"),"attack_up")
	var raised := cast(item,Cases.ATT,"tina")
	check(raised["scenario_ok"] and Stats.power(Loop.unit(raised,"tina"),"attack_up") >= low and raised["last_attack"].get("stat_effects",[]).size() == 1,"magic accepts the smaller source-item strength and uses its own merge")
	var stronger := fixture();Cases.buff(stronger,"tina","attack_up",4,70)
	var extended := Loop.use_item(stronger,"262")
	check(Stats.power(Loop.unit(extended,"tina"),"attack_up") == 70 and extended["last_item_use"]["draws"].is_empty() and (Stats.word(Loop.unit(extended,"tina"),"attack_up") & 65535) == 7,"item after stronger magic preserves all its original power and extends only time")
	var defensive := Loop.use_item(fixture(),"263","companion")
	var ally := Loop.unit(defensive,"companion")
	check(Stats.power(ally,"defense_up") in range(5,11) and (Stats.word(ally,"defense_up") & 65535) == 3,"adjacent recipient gains exactly one source item enhancement")
	var growth := Loop.ProgressionRules.resolve_experience(ally,100,defensive["equipment_items"])
	check(Stats.word(growth,"defense_up") == Stats.word(ally,"defense_up") and Loop.ProgressionRules.enhancement_profile_error(growth,defensive["equipment_items"]) == "","level refresh keeps low-strength item enhancements exactly once")
	var dispelled := cast(defensive,Cases.DISPEL,"enemy026_1")
	check(dispelled["units"] == defensive["units"] and no_draw(dispelled, defensive, "damage"),"unbuffed enemy cannot consume a false dispel or draw from the damage stream")
	var cursor := Loop.use_item(fixture(),"263")
	var saved_word := Stats.word(Loop.unit(cursor,"tina"),"defense_up")
	for _n in range(30):
		if Stats.word(Loop.unit(cursor,"tina"),"defense_up") == 0: break
		if cursor["interaction"] == "ai_resolving": cursor = Loop.step_ai_turn(cursor,func(_bound):return 0)
		else: cursor = Loop.choose_command(cursor,"wait")
	check(saved_word != 0 and Stats.word(Loop.unit(cursor,"tina"),"defense_up") == 0 and cursor["last_action_end"]["expired"].has("defense_up"),"actual independent actions and queue cycles expire the local enhancement")
	check(Loop.unit(cursor,"tina")["combat_profile"]["live_defense"] == Loop.unit(base,"tina")["combat_profile"]["live_defense"],"item expiry restores exact base/equipment defense")

func ai_and_saves() -> void:
	for self_cure in [true,false]:
		var loop := fixture();var actor := Loop._unit(loop,"tina")
		actor["player_commandable"] = false;actor["battle_actor_role"] = Loop.ROLE_FRIENDLY;actor["no_attack"] = true
		actor["inventory"] = [247,0,0,0,0,0,0,0]
		var target := actor if self_cure else Loop._unit(loop,"companion")
		target.merge(Loop.StatusEffectRules.apply(target,"no_magic",3)["changes"],true)
		if self_cure: Loop._unit(loop,"companion")["hp"] = 1
		own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":100 if self_cure else 0,"ai_help_status":100,"ai_help_attack":0,"ai_att_magic":100 if self_cure else 0},true)
		own(loop, "skill_book")["skills"][Priest.HEAL]["fields"]["use_ratio"] = "100"
		loop["interaction"] = "ai_resolving";loop["selected_unit_id"] = ""
		var first := Loop.step_ai_turn(loop,func(_n):return 0)
		check(first["scenario_ok"] and first["last_item_use"].get("item_code") == "247" and first["extra_action"]["pending"],"AI commits first matching silence cure on self/ally")
		check(not Loop.StatusEffectRules.magic_blocked(Loop.unit(first,target["id"])) and no_draw(first, loop, "damage"),"AI cure clears actual target without artificial item random draws")
		var second := Loop.step_ai_turn(first,func(_n):return 0)
		if self_cure: check(second["last_ai_action"].get("skill_id") == Priest.HEAL and second["last_ai_action"].get("healing",0) > 0,"AI rebuilds owned healing after its first-action silence cure")
		else: check(second["item_use_sequence"] == 1,"AI does not repeat a consumed/unneeded ally cure")
	var used := Loop.use_item(fixture(),"262")
	var snapshot := Save.encode(used,VIEW)
	check(snapshot["ok"],"snapshot records exactly one random item application")
	if snapshot["ok"]:
		var loaded := Save.decode(snapshot["bytes"], used)
		check(loaded["ok"] and loaded["snapshot"]["loop"] == used,"decode validates past item effect without applying it a second time")
		var one := Loop.use_item(used,"263")
		var two := Loop.use_item(loaded["snapshot"]["loop"],"263")
		check(one == two,"same saved stream yields identical subsequent defense, inventory and final tail")
	for part in ["rng","sequence"]:
		var bad := used.duplicate(true)
		if part == "rng":set_stream(bad, "damage", [0])
		elif part == "sequence":bad["item_use_sequence"] += 1
		check(not Save.encode(bad,VIEW)["ok"],"tampered tactical effect proof is rejected: "+part)
	var no_item := fixture()
	check(Loop.use_item(no_item,"262","tina",7) == no_item,"stale inventory index cannot consume another slot or draw")

func terminal_guards() -> void:
	for mode in ["victory","defeat","escape"]:
		var loop := fixture();var actor := Loop._unit(loop,"tina");var foe := Loop._unit(loop,"enemy026_1")
		actor["hit_bonus_accum"] = 1000;foe["coord"] = Vector2i(15,16)
		if mode == "victory":foe["hp"] = 1
		if mode == "defeat":
			actor["hp"] = 1;foe["no_attack"] = false;foe["hit_bonus_accum"] = 1000
			foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":1000},true)
			foe.merge(Loop.ProgressionRules.refresh_growth_stats(foe,loop["equipment_items"]),true)
		if mode == "escape":
			actor["coord"] = Vector2i(13,10);Loop._unit(loop,"companion")["coord"] = Vector2i(13,11);foe["coord"] = Vector2i(12,10)
		loop = Loop.use_item(loop,"263")
		var random_after: Array = stream_of(loop, "damage").duplicate()
		if mode == "escape":loop = Loop.choose_command(Loop.move_unit_to(Loop.choose_command(loop,"move"),Vector2i(14,10)),"wait")
		else:loop = Loop.attack_target(Loop.choose_command(loop,"attack"),"enemy026_1",func(_n):return 0)
		check(loop["battle_outcome"] == {"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"tactical item second action reaches "+mode)
		check(stream_of(loop, "damage") == random_after and not loop["extra_action"]["pending"],"terminal freezes the damage stream (the scripted strike brings its own draws) and remaining action")
		check(Loop.use_item(loop,"262") == loop and LoopInventory._resolve_item_use(loop,"tina","tina","262",0).is_empty() and Loop.step_ai_turn(loop) == loop,"no direct or UI item path can continue after terminal")
		check(Save.encode(loop,VIEW)["ok"],"terminal tactical receipt remains restorable")
