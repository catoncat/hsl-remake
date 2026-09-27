extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const run_tactical_items_tests = preload("res://tests/run_tactical_items_tests.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleItemText = preload("res://game/battle/scene/BattleItemText.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BattleLoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const CARRY_PATH := "res://ignored/permanent-carry-tests/progress.json"
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}


func _init() -> void:
	tag = "PERMANENT_ITEMS_TESTS"


static func initial() -> Dictionary:
	return BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/permanent_items_trial.json"))

static func fixture() -> Dictionary:
	var loop := run_tactical_items_tests.fixture()
	var config := initial()
	for key in ["scenario_path","scenario_title","consumables"]:
		loop[key] = config[key].duplicate(true) if config[key] is Dictionary else config[key]
	BattlePlayLoop._unit(loop,"tina")["inventory"] = [253,253,254,255,256,257,257,247]
	return loop

static func totals(actor: Dictionary) -> Dictionary:
	var result := {}
	for key in PermanentCapabilityRules.KEYS: result[key] = PermanentCapabilityRules.base_value(actor,key) + int(actor["permanent_gains"][key])
	return result

static func derived(actor: Dictionary) -> Dictionary:
	var profile: Dictionary = actor["combat_profile"]
	var result := {"attack":profile["live_attack_damage"],"defense":profile["live_defense"],"magic_attack":profile["live_magic_attack"],"speed":actor["live_speed"],"max_hp":actor["max_hp"],"max_mp":actor["max_mp"],"move_point":actor["move_point"]}
	for i in range(5): result["resist_"+str(i)] = profile["resist_by_type"][str(i)]
	return result

func assert_values(actor: Dictionary, values: Dictionary, label: String) -> void:
	var actual := derived(actor)
	for key in values: check(int(actual[key]) == int(values[key]),label+": "+key)

func run() -> void:
	check(initial()["scenario_ok"],"public permanent-item trial initializes through the production loop")
	if not initial()["scenario_ok"]: return
	native_cases()
	transactions()
	resistance_caps()
	magic_and_protection()
	states_growth_and_combat()
	ai_and_queue()
	saved_and_terminal()
	carry_cases()

func native_cases() -> void:
	var base := BattleFixture.loop()
	var priest := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/priest_trial.json"))
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_permanent_items.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var units: Array = priest["units"] if input["actor"] == "002" else base["units"]
		var actor: Dictionary = units.filter(func(a):return a["actor_id"]==input["actor"])[0].duplicate(true)
		var source: Dictionary = actor["growth_profile"].duplicate(true)
		actor.merge({"level":int(input["level"]),"hp":1,"mp":0,"stamina":20,"exp":37,
			"status_flags":7|(0x30 if input["enhanced"] else 0),"status_counters":{"poison":0x70003,"no_magic":3,"paralysis":2,"attack_up":0x60004 if input["enhanced"] else 0,"defense_up":0x1e0004 if input["enhanced"] else 0}},true)
		for key in PermanentCapabilityRules.KEYS: actor["permanent_gains"][key] = int(row["initial"][key]) - PermanentCapabilityRules.base_value(actor,key)
		actor = ProgressionRules.refresh_growth_stats(actor,base["equipment_items"])
		assert_values(actor,row["initial_values"],"original source initialization")
		for part in row["applications"]:
			var ready := BattlePlayLoop.ItemUseRules.prepare(actor,base["consumables"][str(int(input["code"]))])
			if not ready["ok"]:
				check(ready["reason"]=="item_has_no_effect" and part["before"]==part["after"],"cap refusal is explicit remake policy over a native unchanged raw value")
			else:
				check(ready["permanent_proposals"].size()==1,"one source permanent field creates one proposal")
				var proposal: Dictionary = ready["permanent_proposals"][0]
				PermanentCapabilityRules.apply_sample(actor,proposal,int(proposal["low"])+int(part["draws"][0]["value"]))
				actor = ProgressionRules.refresh_growth_stats(actor,base["equipment_items"])
			for key in PermanentCapabilityRules.KEYS: check(totals(actor)[key]==int(part["after"][key]),"native item updates exact persistent source: "+key)
			assert_values(actor,part["values"],"native item internal refresh")
		for part in row["refreshes"]:
			actor["level"] = int(part["level"]); actor["equipment"] = []
			for i in range(6):
				var code := int(part["equipment"][i])
				if code > 0: actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[i],"item_code":code})
			actor = ProgressionRules.refresh_growth_stats(actor,base["equipment_items"])
			assert_values(actor,part["values"],"original complete "+part["kind"])
			check(actor["growth_profile"]==source and actor["hp"]==1 and actor["mp"]==0 and actor["stamina"]==20 and actor["exp"]==37,"refresh never edits the source template or grants resources/EXP")

func transactions() -> void:
	for code in range(253,262):
		var loop := fixture(); var owner := BattlePlayLoop._unit(loop,"tina")
		owner["inventory"] = [code,code,0,0,0,0,0,0]
		var saved := loop.duplicate(true)
		var key: String = loop["consumables"][str(code)]["permanent"].keys()[0]
		var preview := BattlePlayLoop.ItemUseRules.prepare(owner,loop["consumables"][str(code)])
		check(preview["ok"] and BattleItemText.preview(preview,loop["consumables"][str(code)]).contains("永久") and loop==saved,"preview exposes permanent meaning without spending or sampling")
		var first := BattlePlayLoop.use_item(loop,str(code))
		check(first["scenario_ok"] and first["item_use_sequence"]==1 and first["extra_action"]["pending"],"first actual permanent use commits one independent action")
		var receipt: Dictionary = first["last_item_use"]
		var after := BattlePlayLoop.unit(first,"tina")
		check(receipt["draws"].size()==1 and receipt["draws"][0]["bound"]==(1 if code>=257 else 5),"source permanent sampler including fixed resistance1 still advances once")
		check(after["inventory"]==[code,0,0,0,0,0,0,0] and int(after["permanent_gains"][key])==int(receipt["permanent_effects"][0]["amount"]),"one actual slot is consumed for exactly the acquired source amount")
		for attribute in ["str","dex","mind","con"]: check(after["combat_profile"][attribute]==owner["combat_profile"][attribute],"permanent derived offset never changes basic "+attribute)
		for value in ["hp","mp","stamina","exp","max_hp","max_mp","move_point"]: check(after[value]==owner[value],"permanent item does not refill or alter unrelated "+value)
		var second := BattlePlayLoop.use_item(first,str(code))
		check(second["item_use_sequence"]==2 and second["action_end_sequence"]==1,"two actual uses advance the item stream twice and final-action tail once")
		check(BattlePlayLoop.unit(second,"tina")["permanent_gains"][key]==int(receipt["permanent_effects"][0]["amount"])+int(second["last_item_use"]["permanent_effects"][0]["amount"]),"repeated permanent consumables add distinct gains, unlike duration-only temporary items")
		check(BattlePlayLoop.unit(second,"tina")["growth_profile"]==owner["growth_profile"] and loop==saved,"source and caller input remain immutable")
		check(BattlePlayLoop.use_item(second,str(code))==second,"late repeat cannot consume absent inventory or act for a different owner")

func resistance_caps() -> void:
	var loop := fixture(); var actor := BattlePlayLoop._unit(loop,"tina")
	actor["permanent_gains"]["resist_0"] = 79 - PermanentCapabilityRules.base_value(actor,"resist_0")
	actor.merge(ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var used := BattlePlayLoop.use_item(loop,"257")
	var after := BattlePlayLoop.unit(used,"tina")
	check(totals(after)["resist_0"]==80 and after["combat_profile"]["resist_by_type"]["0"]==80,"intrinsic and visible resistance separately reach80")
	var capped := BattlePlayLoop.use_item(used,"257"); var held := BattlePlayLoop.unit(capped,"tina")
	check(capped["item_use_sequence"]==used["item_use_sequence"]+1 and capped["last_item_use"]["draws"].size()==1 and int(capped["last_item_use"]["permanent_effects"][0]["amount"])==0 and totals(held)["resist_0"]==80 and held["inventory"].count(257)==after["inventory"].count(257)-1,"raw cap still spends the item and draws once for a 0 gain (0x444aba; original_permanent_items.json cap rows)")
	var visible := fixture(); actor=BattlePlayLoop._unit(visible,"tina")
	var original := int(actor["combat_profile"]["resist_by_type"]["0"])
	actor["permanent_gains"]["resist_0"] = 75 - original
	actor["equipment"].append({"slot":"accessory1","item_code":207}) # Source Earth ring contributes five resistance points.
	actor.merge(ProgressionRules.refresh_growth_stats(actor,visible["equipment_items"]),true)
	check(actor["combat_profile"]["resist_by_type"]["0"]==80 and totals(actor)["resist_0"]<80,"equipment can cap display while intrinsic growth remains useful")
	var receipt := BattlePlayLoop.use_item(visible,"257")
	check(BattlePlayLoop.unit(receipt,"tina")["combat_profile"]["resist_by_type"]["0"]==80 and receipt["item_use_sequence"]==1,"display cap does not discard a legitimate intrinsic gain")
	var removed := BattlePlayLoop.change_equipment(receipt,"accessory1",-1,0)
	check(BattlePlayLoop.unit(removed,"tina")["combat_profile"]["resist_by_type"]["0"]==76,"removing resistance gear reveals the preserved one-point permanent increase")

func magic_and_protection() -> void:
	var loop := fixture()
	var caster := BattlePlayLoop._unit(loop,"tina")
	var target := BattlePlayLoop._unit(loop,"enemy026_1")
	var wind := "magic:magicAIR:magicCode01"
	own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"].append(wind)
	caster["inventory"] = [255,0,0,0,0,0,0,0]
	var baseline := BattlePlayLoop.SkillResolutionRules.resolve(caster,target,wind,BattlePlayLoop.skill_fields(loop,wind),loop["skill_book"],loop["skill_target_data"],loop["equipment_items"],caster["coord"],loop["map_size"],func(_bound):return 0)
	var gained := BattlePlayLoop.use_item(loop,"255")
	var after := BattlePlayLoop.unit(gained,"tina")
	var increased := BattlePlayLoop.SkillResolutionRules.resolve(after,target,wind,BattlePlayLoop.skill_fields(gained,wind),gained["skill_book"],gained["skill_target_data"],gained["equipment_items"],after["coord"],gained["map_size"],func(_bound):return 0)
	check(baseline["ok"] and increased["ok"] and increased["receipt"]["actual_damage"]>=baseline["receipt"]["actual_damage"] and increased["receipt"]["resource_payment"]==baseline["receipt"]["resource_payment"],"actual acquired magic power reaches existing wind math without changing MP cost")
	for pair in [[257,"0","magic:magicEARTH:magicCode05"],[260,"2","magic:magicAIR:magicCode05"],[261,"4","magic:magicMIND:magicCode02"]]:
		loop = fixture();caster = BattlePlayLoop._unit(loop,"tina");target = BattlePlayLoop._unit(loop,"enemy026_1")
		var key: String = "resist_"+pair[1]
		caster["permanent_gains"][key] = 79-PermanentCapabilityRules.base_value(caster,key)
		caster["inventory"] = [pair[0],0,0,0,0,0,0,0]
		caster.merge(ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true)
		var old := BattlePlayLoop.StatusApplicationRules.prepare(target,caster,BattlePlayLoop.skill_fields(loop,pair[2]),loop["skill_book"],loop["skill_target_data"],loop["equipment_items"])
		gained = BattlePlayLoop.use_item(loop,str(pair[0]));after = BattlePlayLoop.unit(gained,"tina")
		var ready := BattlePlayLoop.StatusApplicationRules.prepare(target,after,BattlePlayLoop.skill_fields(gained,pair[2]),gained["skill_book"],gained["skill_target_data"],gained["equipment_items"])
		check(ready["ok"] and ready["roll_input"]["resistance"]==80 and ready["immunities"]==old["immunities"] and ready["roll_input"]["status_hit_ratio"]==old["roll_input"]["status_hit_ratio"],"permanent resistance enters numeric roll without inventing an immunity or status hit rate")

func states_growth_and_combat() -> void:
	var loop := fixture(); var actor := BattlePlayLoop._unit(loop,"tina")
	actor["exp"] = 99
	actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
	run_support_magic_tests.buff(loop,"tina","attack_up",3,24);run_support_magic_tests.buff(loop,"tina","defense_up",3,30)
	var original: Dictionary = actor["status_counters"].duplicate(true)
	var applied := BattlePlayLoop.use_item(loop,"253")
	actor = BattlePlayLoop.unit(applied,"tina")
	check(actor["status_counters"]==original and actor["exp"]==99,"permanent item under poison/silence preserves temporary counters until final action and grants no EXP")
	var upgraded := ProgressionRules.resolve_experience(actor,1,applied["equipment_items"])
	check(upgraded["level"]==actor["level"]+1 and upgraded["permanent_gains"]==actor["permanent_gains"] and upgraded["growth_profile"]==actor["growth_profile"],"final EXP refresh preserves acquired offsets and immutable source")
	var allocated := ProgressionRules.apply_allocation(upgraded,{"str":1},applied["equipment_items"])
	check(allocated["combat_profile"]["str"]==upgraded["combat_profile"]["str"]+1 and allocated["permanent_gains"]==upgraded["permanent_gains"],"manual growth points and permanent item sources remain separate")
	var caster := BattlePlayLoop._unit(applied,"enemy026_1")
	caster["mp"] = caster["max_mp"]
	own(applied, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_support_magic_tests.DISPEL]
	var dispelled := BattlePlayLoop.SkillResolutionRules.resolve_cast(caster,actor,applied["units"],run_support_magic_tests.DISPEL,BattlePlayLoop.skill_fields(applied,run_support_magic_tests.DISPEL),applied["skill_book"],applied["skill_target_data"],applied["equipment_items"],caster["coord"],applied["map_size"],zero)
	check(dispelled["ok"],"enemy dispel can act on the temporary layer around a permanently improved target")
	if dispelled["ok"]:
		var target := actor.duplicate(true);target.merge(dispelled["target_changes"],true)
		check(target["permanent_gains"]==actor["permanent_gains"] and target["status_counters"]["poison"]==original["poison"] and target["status_counters"]["no_magic"]==3,"dispel leaves permanent gain, poison and silence untouched")
		check(target["combat_profile"]["live_attack_damage"]==actor["combat_profile"]["live_attack_damage"]-24,"dispel removes only temporary attack")
	var blocked := fixture(); var stunned:=BattlePlayLoop._unit(blocked,"tina")
	stunned.merge(BattlePlayLoop.StatusEffectRules.apply(stunned,"paralysis",2)["changes"],true)
	check(BattlePlayLoop.use_item(blocked,"253")==blocked,"paralyzed owner cannot spend a permanent consumable")
	var recipient:=BattlePlayLoop._unit(blocked,"companion");recipient["inventory"]=[253,0,0,0,0,0,0,0]
	var aid:=BattlePlayLoop.ItemResolutionRules.prepare(recipient,stunned,"253",0,blocked["consumables"]["253"],blocked["equipment_items"],DamageRandomStream.seeded(1),1)
	check(aid["ok"] and aid["target_changes"]["status_counters"]["paralysis"]==2,"living paralyzed recipient may receive an ally's item without cure or owner action")
	var battle:=fixture();var foe:=BattlePlayLoop._unit(battle,"enemy026_1")
	foe["coord"]=Vector2i(15,16);foe["no_attack"]=false;foe["hit_bonus_accum"]=1000;foe["growth_profile"]["source"]["attack_back"]=100
	foe.merge(ProgressionRules.refresh_growth_stats(foe,battle["equipment_items"]),true)
	BattlePlayLoop._unit(battle,"tina")["hit_bonus_accum"]=1000
	own(battle, "skill_book")["actors"]["002"]["double_attack"]=true;own(battle, "skill_book")["actors"]["026"]["double_attack"]=true
	battle=BattlePlayLoop.use_item(battle,"254")
	var gain: Dictionary=BattlePlayLoop.unit(battle,"tina")["permanent_gains"].duplicate(true)
	var exchange:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(battle,"attack"),"enemy026_1",zero)
	check(exchange["scenario_ok"] and exchange["last_attack"].get("followups",[]).size()==1,"permanent defense enters the actual two-hit ordinary/counter transaction")
	check(BattlePlayLoop.unit(exchange,"tina")["permanent_gains"]==gain and exchange["item_use_sequence"]==1,"multiple attack/counter hits do not reapply or consume the permanent item")

func ai_and_queue() -> void:
	var loop:=fixture();var actor:=BattlePlayLoop._unit(loop,"tina");var ally:=BattlePlayLoop._unit(loop,"companion")
	ally["growth_profile"]["source"]["speed"]+=int(actor["live_speed"])-int(ally["live_speed"])-1
	ally.merge(ProgressionRules.refresh_growth_stats(ally,loop["equipment_items"]),true)
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	for seed_value in range(1,100):
		if DamageRandomStream.rand(DamageRandomStream.seeded(seed_value),5)["value"]==4:seed_stream(loop, "damage", seed_value);break
	var slots: Array=loop["turn_queue"]["slots"].duplicate(true)
	var first:=BattlePlayLoop.use_item(loop,"256","companion")
	check(first["turn_queue"]["slots"]==slots and BattlePlayLoop.unit(first,"companion")["live_speed"]>actor["live_speed"],"speed gain updates the actor but never reorders an action already in progress")
	first=BattlePlayLoop.choose_command(first,"wait");first=BattlePlayLoop.choose_command(first,"wait")
	first=BattlePlayLoop.step_ai_turn(first,zero)
	check(first["scenario_ok"] and BattlePlayLoop.CoreTurnQueue.current(first["turn_queue"])["id"]=="companion","next real round sorts the acquired speed at the existing queue rebuild")
	var aid:=fixture();var helper:=BattlePlayLoop._unit(aid,"companion")
	helper["inventory"]=[253,0,0,0,0,0,0,0];helper["player_commandable"]=false;helper["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY
	var foe:=BattlePlayLoop._unit(aid,"enemy026_1");foe["coord"]=Vector2i(15,15)
	aid=BattlePlayLoop.use_item(aid,"253","companion");aid=BattlePlayLoop.choose_command(aid,"wait")
	var response:=BattlePlayLoop.step_ai_turn(aid,zero)
	check(response["scenario_ok"] and response["last_ai_action"]["kind"] in ["attack","move_then_attack"],"AI with acquired attack uses its current legal combat action")
	check(BattlePlayLoop.unit(response,"companion")["inventory"]==[253,0,0,0,0,0,0,0] and response["item_use_sequence"]==1,"unproven proactive rare-item consumption is not introduced")

func saved_and_terminal() -> void:
	var used:=BattlePlayLoop.use_item(fixture(),"255")
	var unsupported := fixture()
	var unknown := BattlePlayLoop._unit(unsupported,"tina")
	unknown.erase("growth_profile")
	check(PermanentCapabilityRules.input_error(unknown)=="" and ExperienceRules.input_error(unsupported,unknown)=="","an existing no-growth combat actor remains valid with an empty acquired ledger")
	var unchanged := unsupported.duplicate(true)
	check(BattlePlayLoop.ItemUseRules.prepare(unknown,unsupported["consumables"]["253"])["reason"]=="missing_permanent_source" and BattlePlayLoop.use_item(unsupported,"253")==unchanged,"unproven growth source rejects permanent use before consumption or random advance")
	unknown["permanent_gains"]["attack_power"]=1
	check(PermanentCapabilityRules.input_error(unknown)=="missing_permanent_source","missing source cannot conceal an already acquired permanent value")
	unknown["permanent_gains"]["attack_power"]=0
	unknown["growth_profile"]={}
	check(PermanentCapabilityRules.input_error(unknown)!="","a present malformed growth source is never treated as the intentional no-growth case")
	var saved:=BattleCheckpoint.encode(used,VIEW)
	check(saved["ok"],"permanent use has a complete replayable checkpoint")
	if saved["ok"]:
		var restored:=BattleCheckpoint.decode(saved["bytes"], used)
		check(restored["ok"] and restored["snapshot"]["loop"]==used,"restoring validates the acquired source without applying it again")
		check(BattlePlayLoop.use_item(used,"253")==BattlePlayLoop.use_item(restored["snapshot"]["loop"],"253"),"subsequent random permanent gains and second-action tail are identical after restore")
	for part in ["missing","negative","fraction","unknown","resistance","derived"]:
		var bad:=used.duplicate(true);var actor:=BattlePlayLoop._unit(bad,"tina")
		match part:
			"missing":actor.erase("permanent_gains")
			"negative":actor["permanent_gains"]["speed"]=-1
			"fraction":actor["permanent_gains"]["speed"]=0.5
			"unknown":actor["permanent_gains"]["str"]=1
			"resistance":actor["permanent_gains"]["resist_0"]=80
			"derived":actor["combat_profile"]["live_magic_attack"]+=1
		check(not BattleCheckpoint.encode(bad,VIEW)["ok"],"invalid permanent state or proof rejects before saving: "+part)
	for mode in ["victory","defeat","escape"]:
		var loop:=fixture();var actor:=BattlePlayLoop._unit(loop,"tina");var foe:=BattlePlayLoop._unit(loop,"enemy026_1")
		actor["hit_bonus_accum"]=1000;foe["coord"]=Vector2i(15,16)
		if mode=="victory":foe["hp"]=1;actor["exp"]=99
		if mode=="defeat":
			actor["hp"]=1;foe["no_attack"]=false;foe["hit_bonus_accum"]=1000
			foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":1000},true);foe.merge(ProgressionRules.refresh_growth_stats(foe,loop["equipment_items"]),true)
		if mode=="escape":actor["coord"]=Vector2i(13,10);BattlePlayLoop._unit(loop,"companion")["coord"]=Vector2i(13,11);foe["coord"]=Vector2i(12,10)
		loop=BattlePlayLoop.use_item(loop,"253")
		var gains:Dictionary=BattlePlayLoop.unit(loop,"tina")["permanent_gains"].duplicate(true)
		if mode=="escape":loop=BattlePlayLoop.choose_command(BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop,"move"),Vector2i(14,10)),"wait")
		else:loop=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),"enemy026_1",zero)
		check(loop["battle_outcome"]=={"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"permanent-item second action reaches actual "+mode)
		check(BattlePlayLoop.unit(loop,"tina")["permanent_gains"]==gains and BattleCheckpoint.encode(loop,VIEW)["ok"],"terminal keeps the acquired offset exactly once and remains restorable")
		check(BattlePlayLoop.use_item(loop,"253")==loop and BattlePlayLoop.step_ai_turn(loop)==loop and BattlePlayLoop.finish_exhausted_action(loop)==loop,"terminal cannot resample, spend or act after "+mode)


## Cross-battle carry of acquired permanent gains (formerly run_permanent_carry_tests.gd): the real
## item commit and campaign serialization, with isolated disk paths.
func carry_cases() -> void:
	DirAccess.make_dir_recursive_absolute(CARRY_PATH.get_base_dir())
	var first := BattleFixture.loop()
	# Supplied inventory only; acquired values come from nine production commits.
	for code in range(253,262):
		BattlePlayLoop._unit(first,"leonard")["inventory"] = [code,0,0,0,0,0,0,0]
		check(not BattleLoopInventory._resolve_item_use(first,"leonard","leonard",str(code),0).is_empty(),"actual owned permanent source commits: "+str(code))
	var owner := BattlePlayLoop.unit(first,"leonard")
	check(owner["permanent_gains"].values().all(func(v):return int(v)>0),"all nine acquired offsets are nonzero")
	var campaign := CampaignProgress.load_campaign()
	check(campaign["carry_policy"]["unit_keys"].has("permanent_gains") and CampaignCarryRules.DEFAULT_POLICY["unit_keys"].has("permanent_gains"),"configured and default carry policies both preserve acquired sources")
	var carry := CampaignCarryRules.capture(first,campaign["carry_policy"])
	check(carry["units"]["leonard"]["permanent_gains"]==owner["permanent_gains"],"capture includes nine gains without conversion to basic attributes")
	for forbidden in ["status_counters","status_flags","growth_profile","live_speed","combat_profile"]:
		check(not carry["units"]["leonard"].has(forbidden),"carry never promotes temporary/template/cache fields: "+forbidden)
	var handoff := {"schema":CampaignProgress.SCHEMA,"scenario_path":"res://content/battles/battle_052.json","carry":carry,"from_scenario_id":first["scenario_path"]}
	check(CampaignProgress.save_progress(handoff,CARRY_PATH),"campaign record writes to isolated real file")
	var loaded := CampaignProgress.load_progress(CARRY_PATH)
	check(PermanentCapabilityRules.KEYS.all(func(k):return loaded["carry"]["units"]["leonard"]["permanent_gains"][k]==owner["permanent_gains"][k]),"JSON round-trip preserves all acquired numeric amounts")
	var second := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file(loaded["scenario_path"]))
	var incoming := second.duplicate(true)
	var applied := BattlePlayLoop.apply_campaign_carry(second,loaded["carry"])
	var received := BattlePlayLoop.unit(applied,"leonard")
	check(applied["campaign_carry_receipt"]["errors"].is_empty() and received["permanent_gains"]==owner["permanent_gains"],"new battle installs acquired sources before shared derived refresh")
	check(derived(received)==derived(owner) and received["growth_profile"]==BattlePlayLoop.unit(second,"leonard")["growth_profile"],"next battle derives identical values from its own unchanged source model")
	check(applied["item_use_sequence"]==0 and no_draw(applied, first, "damage") and not no_draw(applied, second, "damage") and received["status_flags"]==0,"handoff never repeats item payment or old temporary status; the campaign damage stream resumes exactly where the first battle left it (JSON round trip)")
	check(second==incoming,"carry apply leaves its input battle immutable")
	var replay := BattlePlayLoop.apply_campaign_carry(applied,loaded["carry"])
	check(replay["units"]==applied["units"],"retrying the same initial handoff replaces sources instead of accumulating")
	var grew := BattlePlayLoop.ProgressionRules.resolve_experience(received,100,applied["equipment_items"])
	check(grew["permanent_gains"]==received["permanent_gains"],"post-handoff level growth keeps gains")
	var no_gear := grew.duplicate(true); no_gear["equipment"] = []
	no_gear = BattlePlayLoop.ProgressionRules.refresh_growth_stats(no_gear,applied["equipment_items"])
	check(no_gear["permanent_gains"]==received["permanent_gains"],"post-handoff equipment removal keeps gains")
	var active := BattlePlayLoop.begin_battle(applied)
	var snapshot := BattleCheckpoint.encode(active,VIEW)
	check(snapshot["ok"],"carried battle is a valid quiet-boundary checkpoint")
	if snapshot["ok"]:
		var restored := BattleCheckpoint.decode(snapshot["bytes"], active)
		check(restored["ok"] and restored["snapshot"]["loop"]==active,"single-battle save after campaign load never reacquires offsets")
	check(BattlePlayLoop.apply_campaign_carry(active,carry)==active,"late campaign application cannot change an active action")
	for bad_value in [-1,0.5,1000001]:
		var broken := carry.duplicate(true); broken["units"]["leonard"]["permanent_gains"]["attack_power"] = bad_value
		var rejected := BattlePlayLoop.apply_campaign_carry(second,broken)
		check(not rejected["campaign_carry_receipt"]["errors"].is_empty() and rejected["units"]==second["units"],"invalid persisted gain is rejected before replacing actor: "+str(bad_value))
	var over_cap := carry.duplicate(true); over_cap["units"]["leonard"]["permanent_gains"]["resist_0"] = 81
	check(BattlePlayLoop.apply_campaign_carry(second,over_cap)["units"]==second["units"],"cross-battle raw resistance above80 is not silently normalized")
	# Story/separate-party handoffs use the same carried record, without applying
	# Leonard's sources to the independent source002 character.
	var third := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_053.json"))
	check(CampaignProgress.separate_party(campaign,"res://content/battles/battle_053.json"),"separate-party scenario retains its policy")
	check(BattlePlayLoop.apply_campaign_carry(third,carry)["units"]==third["units"],"unmatched party never inherits another actor's gains")
	CampaignProgress.pending = loaded
	check(CampaignProgress.take_handoff()["carry"]==loaded["carry"] and not CampaignProgress.has_pending(),"handoff consumes once")
	check(CampaignProgress.take_handoff()["carry"]==loaded["carry"],"retry retains entry gains without reading the previous battle's mutable state")
	CampaignProgress.pending = {}; CampaignProgress.last_entry = {}
	check(BattlePlayLoop.unit(BattleFixture.loop(),"leonard")["permanent_gains"]==PermanentCapabilityRules.empty(),"new campaign starts from source rather than prior acquired offsets")
	CampaignProgress.clear_progress(CARRY_PATH)
