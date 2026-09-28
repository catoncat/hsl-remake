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
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
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
	BattlePlayLoop.unit_ref(loop,"tina")["inventory"] = [253,253,254,255,256,257,257,247]
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
	resistance_caps()
	magic_and_protection()
	states_growth_and_combat()
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

func resistance_caps() -> void:
	var loop := fixture(); var actor := BattlePlayLoop.unit_ref(loop,"tina")
	actor["permanent_gains"]["resist_0"] = 79 - PermanentCapabilityRules.base_value(actor,"resist_0")
	actor.merge(ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var used := BattlePlayLoop.use_item(loop,"257")
	var after := BattlePlayLoop.unit(used,"tina")
	check(totals(after)["resist_0"]==80 and after["combat_profile"]["resist_by_type"]["0"]==80,"intrinsic and visible resistance separately reach80")
	var capped := BattlePlayLoop.use_item(used,"257"); var held := BattlePlayLoop.unit(capped,"tina")
	check(capped["item_use_sequence"]==used["item_use_sequence"]+1 and capped["last_item_use"]["draws"].size()==1 and int(capped["last_item_use"]["permanent_effects"][0]["amount"])==0 and totals(held)["resist_0"]==80 and held["inventory"].count(257)==after["inventory"].count(257)-1,"raw cap still spends the item and draws once for a 0 gain (0x444aba; original_permanent_items.json cap rows)")
	var visible := fixture(); actor=BattlePlayLoop.unit_ref(visible,"tina")
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
	var caster := BattlePlayLoop.unit_ref(loop,"tina")
	var target := BattlePlayLoop.unit_ref(loop,"enemy026_1")
	var wind := "magic:magicAIR:magicCode01"
	own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"].append(wind)
	caster["inventory"] = [255,0,0,0,0,0,0,0]
	var baseline := BattlePlayLoop.SkillResolutionRules.resolve(caster,target,wind,BattlePlayLoop.skill_fields(loop,wind),loop["skill_book"],loop["skill_target_data"],loop["equipment_items"],caster["coord"],loop["map_size"],func(_bound):return 0)
	var gained := BattlePlayLoop.use_item(loop,"255")
	var after := BattlePlayLoop.unit(gained,"tina")
	var increased := BattlePlayLoop.SkillResolutionRules.resolve(after,target,wind,BattlePlayLoop.skill_fields(gained,wind),gained["skill_book"],gained["skill_target_data"],gained["equipment_items"],after["coord"],gained["map_size"],func(_bound):return 0)
	check(baseline["ok"] and increased["ok"] and increased["receipt"]["actual_damage"]>=baseline["receipt"]["actual_damage"] and increased["receipt"]["resource_payment"]==baseline["receipt"]["resource_payment"],"actual acquired magic power reaches existing wind math without changing MP cost")
	for pair in [[257,"0","magic:magicEARTH:magicCode05"],[260,"2","magic:magicAIR:magicCode05"],[261,"4","magic:magicMIND:magicCode02"]]:
		loop = fixture();caster = BattlePlayLoop.unit_ref(loop,"tina");target = BattlePlayLoop.unit_ref(loop,"enemy026_1")
		var key: String = "resist_"+pair[1]
		caster["permanent_gains"][key] = 79-PermanentCapabilityRules.base_value(caster,key)
		caster["inventory"] = [pair[0],0,0,0,0,0,0,0]
		caster.merge(ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true)
		var old := BattlePlayLoop.StatusApplicationRules.prepare(target,caster,BattlePlayLoop.skill_fields(loop,pair[2]),loop["skill_book"],loop["skill_target_data"],loop["equipment_items"])
		gained = BattlePlayLoop.use_item(loop,str(pair[0]));after = BattlePlayLoop.unit(gained,"tina")
		var ready := BattlePlayLoop.StatusApplicationRules.prepare(target,after,BattlePlayLoop.skill_fields(gained,pair[2]),gained["skill_book"],gained["skill_target_data"],gained["equipment_items"])
		check(ready["ok"] and ready["roll_input"]["resistance"]==80 and ready["immunities"]==old["immunities"] and ready["roll_input"]["status_hit_ratio"]==old["roll_input"]["status_hit_ratio"],"permanent resistance enters numeric roll without inventing an immunity or status hit rate")

func states_growth_and_combat() -> void:
	var loop := fixture(); var actor := BattlePlayLoop.unit_ref(loop,"tina")
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
	var caster := BattlePlayLoop.unit_ref(applied,"enemy026_1")
	caster["mp"] = caster["max_mp"]
	own(applied, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_support_magic_tests.DISPEL]
	var dispelled := BattlePlayLoop.SkillResolutionRules.resolve_cast(caster,actor,applied["units"],run_support_magic_tests.DISPEL,BattlePlayLoop.skill_fields(applied,run_support_magic_tests.DISPEL),applied["skill_book"],applied["skill_target_data"],applied["equipment_items"],caster["coord"],applied["map_size"],zero)
	check(dispelled["ok"],"enemy dispel can act on the temporary layer around a permanently improved target")
	if dispelled["ok"]:
		var target := actor.duplicate(true);target.merge(dispelled["target_changes"],true)
		check(target["permanent_gains"]==actor["permanent_gains"] and target["status_counters"]["poison"]==original["poison"] and target["status_counters"]["no_magic"]==3,"dispel leaves permanent gain, poison and silence untouched")
		check(target["combat_profile"]["live_attack_damage"]==actor["combat_profile"]["live_attack_damage"]-24,"dispel removes only temporary attack")
	var blocked := fixture(); var stunned:=BattlePlayLoop.unit_ref(blocked,"tina")
	stunned.merge(BattlePlayLoop.StatusEffectRules.apply(stunned,"paralysis",2)["changes"],true)
	check(BattlePlayLoop.use_item(blocked,"253")==blocked,"paralyzed owner cannot spend a permanent consumable")
	var recipient:=BattlePlayLoop.unit_ref(blocked,"companion");recipient["inventory"]=[253,0,0,0,0,0,0,0]
	var aid:=BattlePlayLoop.ItemResolutionRules.prepare(recipient,stunned,"253",0,blocked["consumables"]["253"],blocked["equipment_items"],DamageRandomStream.seeded(1),1)
	check(aid["ok"] and aid["target_changes"]["status_counters"]["paralysis"]==2,"living paralyzed recipient may receive an ally's item without cure or owner action")
	var battle:=fixture();var foe:=BattlePlayLoop.unit_ref(battle,"enemy026_1")
	foe["coord"]=Vector2i(15,16);foe["no_attack"]=false;foe["hit_bonus_accum"]=1000;foe["growth_profile"]["source"]["attack_back"]=100
	foe.merge(ProgressionRules.refresh_growth_stats(foe,battle["equipment_items"]),true)
	BattlePlayLoop.unit_ref(battle,"tina")["hit_bonus_accum"]=1000
	own(battle, "skill_book")["actors"]["002"]["double_attack"]=true;own(battle, "skill_book")["actors"]["026"]["double_attack"]=true
	battle=BattlePlayLoop.use_item(battle,"254")
	var gain: Dictionary=BattlePlayLoop.unit(battle,"tina")["permanent_gains"].duplicate(true)
	var exchange:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(battle,"attack"),"enemy026_1",zero)
	check(exchange["scenario_ok"] and exchange["last_attack"].get("followups",[]).size()==1,"permanent defense enters the actual two-hit ordinary/counter transaction")
	check(BattlePlayLoop.unit(exchange,"tina")["permanent_gains"]==gain and exchange["item_use_sequence"]==1,"multiple attack/counter hits do not reapply or consume the permanent item")

func carry_cases() -> void:
	DirAccess.make_dir_recursive_absolute(CARRY_PATH.get_base_dir())
	var first := BattleFixture.loop()
	# Supplied inventory only; acquired values come from nine production commits.
	for code in range(253,262):
		BattlePlayLoop.unit_ref(first,"leonard")["inventory"] = [code,0,0,0,0,0,0,0]
		check(not BattleLoopInventory.resolve_item_use(first,"leonard","leonard",str(code),0).is_empty(),"actual owned permanent source commits: "+str(code))
	var owner := BattlePlayLoop.unit(first,"leonard")
	check(owner["permanent_gains"].values().all(func(v):return int(v)>0),"all nine acquired offsets are nonzero")
	var campaign := CampaignProgress.load_campaign()
	var carry := CampaignCarryRules.capture(first,campaign["carry_policy"])
	check(carry["units"]["leonard"]["permanent_gains"]==owner["permanent_gains"],"capture includes nine gains without conversion to basic attributes")
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
	check(BattlePlayLoop.apply_campaign_carry(third,carry)["units"]==third["units"],"unmatched party never inherits another actor's gains")
	CampaignProgress.pending = loaded
	check(CampaignProgress.take_handoff()["carry"]==loaded["carry"] and not CampaignProgress.has_pending(),"handoff consumes once")
	check(CampaignProgress.take_handoff()["carry"]==loaded["carry"],"retry retains entry gains without reading the previous battle's mutable state")
	CampaignProgress.pending = {}; CampaignProgress.last_entry = {}
	check(BattlePlayLoop.unit(BattleFixture.loop(),"leonard")["permanent_gains"]==PermanentCapabilityRules.empty(),"new campaign starts from source rather than prior acquired offsets")
	CampaignProgress.clear_progress(CARRY_PATH)
