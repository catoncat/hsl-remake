extends "res://tests/support/TestSuite.gd"
## Uses the real item commit and campaign serialization, with isolated disk paths.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopInventory = preload("res://game/battle/scene/BattleLoopInventory.gd")
const Campaign = preload("res://game/battle/runtime/CampaignProgress.gd")
const Carry = preload("res://game/sim/CampaignCarryRules.gd")
const Permanent = preload("res://game/sim/PermanentCapabilityRules.gd")
const Cases = preload("res://tests/run_permanent_items_tests.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const PATH := "res://ignored/permanent-carry-tests/progress.json"


func _init() -> void:
	tag = "PERMANENT_CARRY_TESTS"


func run() -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	var first := BattleFixture.loop()
	# Supplied inventory only; acquired values come from nine production commits.
	for code in range(253,262):
		Loop._unit(first,"leonard")["inventory"] = [code,0,0,0,0,0,0,0]
		check(not LoopInventory._resolve_item_use(first,"leonard","leonard",str(code),0).is_empty(),"actual owned permanent source commits: "+str(code))
	var owner := Loop.unit(first,"leonard")
	check(owner["permanent_gains"].values().all(func(v):return int(v)>0),"all nine acquired offsets are nonzero")
	var campaign := Campaign.load_campaign()
	check(campaign["carry_policy"]["unit_keys"].has("permanent_gains") and Carry.DEFAULT_POLICY["unit_keys"].has("permanent_gains"),"configured and default carry policies both preserve acquired sources")
	var carry := Carry.capture(first,campaign["carry_policy"])
	check(carry["units"]["leonard"]["permanent_gains"]==owner["permanent_gains"],"capture includes nine gains without conversion to basic attributes")
	for forbidden in ["status_counters","status_flags","growth_profile","live_speed","combat_profile"]:
		check(not carry["units"]["leonard"].has(forbidden),"carry never promotes temporary/template/cache fields: "+forbidden)
	var handoff := {"schema":Campaign.SCHEMA,"scenario_path":"res://content/battles/battle_052.json","carry":carry,"from_scenario_id":first["scenario_path"]}
	check(Campaign.save_progress(handoff,PATH),"campaign record writes to isolated real file")
	var loaded := Campaign.load_progress(PATH)
	check(Permanent.KEYS.all(func(k):return loaded["carry"]["units"]["leonard"]["permanent_gains"][k]==owner["permanent_gains"][k]),"JSON round-trip preserves all acquired numeric amounts")
	var second := Loop.create([],"",Loop.BattleScenario.load_file(loaded["scenario_path"]))
	var incoming := second.duplicate(true)
	var applied := Loop.apply_campaign_carry(second,loaded["carry"])
	var received := Loop.unit(applied,"leonard")
	check(applied["campaign_carry_receipt"]["errors"].is_empty() and received["permanent_gains"]==owner["permanent_gains"],"new battle installs acquired sources before shared derived refresh")
	check(Cases.derived(received)==Cases.derived(owner) and received["growth_profile"]==Loop.unit(second,"leonard")["growth_profile"],"next battle derives identical values from its own unchanged source model")
	check(applied["item_use_sequence"]==0 and no_draw(applied, first, "damage") and not no_draw(applied, second, "damage") and received["status_flags"]==0,"handoff never repeats item payment or old temporary status; the campaign damage stream resumes exactly where the first battle left it (JSON round trip)")
	check(second==incoming,"carry apply leaves its input battle immutable")
	var replay := Loop.apply_campaign_carry(applied,loaded["carry"])
	check(replay["units"]==applied["units"],"retrying the same initial handoff replaces sources instead of accumulating")
	var grew := Loop.ProgressionRules.resolve_experience(received,100,applied["equipment_items"])
	check(grew["permanent_gains"]==received["permanent_gains"],"post-handoff level growth keeps gains")
	var no_gear := grew.duplicate(true); no_gear["equipment"] = []
	no_gear = Loop.ProgressionRules.refresh_growth_stats(no_gear,applied["equipment_items"])
	check(no_gear["permanent_gains"]==received["permanent_gains"],"post-handoff equipment removal keeps gains")
	var active := Loop.begin_battle(applied)
	var snapshot := Save.encode(active,Cases.VIEW)
	check(snapshot["ok"],"carried battle is a valid quiet-boundary checkpoint")
	if snapshot["ok"]:
		var restored := Save.decode(snapshot["bytes"], active)
		check(restored["ok"] and restored["snapshot"]["loop"]==active,"single-battle save after campaign load never reacquires offsets")
	check(Loop.apply_campaign_carry(active,carry)==active,"late campaign application cannot change an active action")
	for bad_value in [-1,0.5,1000001]:
		var broken := carry.duplicate(true); broken["units"]["leonard"]["permanent_gains"]["attack_power"] = bad_value
		var rejected := Loop.apply_campaign_carry(second,broken)
		check(not rejected["campaign_carry_receipt"]["errors"].is_empty() and rejected["units"]==second["units"],"invalid persisted gain is rejected before replacing actor: "+str(bad_value))
	var over_cap := carry.duplicate(true); over_cap["units"]["leonard"]["permanent_gains"]["resist_0"] = 81
	check(Loop.apply_campaign_carry(second,over_cap)["units"]==second["units"],"cross-battle raw resistance above80 is not silently normalized")
	# Story/separate-party handoffs use the same carried record, without applying
	# Leonard's sources to the independent source002 character.
	var third := Loop.create([],"",Loop.BattleScenario.load_file("res://content/battles/battle_053.json"))
	check(Campaign.separate_party(campaign,"res://content/battles/battle_053.json"),"separate-party scenario retains its policy")
	check(Loop.apply_campaign_carry(third,carry)["units"]==third["units"],"unmatched party never inherits another actor's gains")
	Campaign.pending = loaded
	check(Campaign.take_handoff()["carry"]==loaded["carry"] and not Campaign.has_pending(),"handoff consumes once")
	check(Campaign.take_handoff()["carry"]==loaded["carry"],"retry retains entry gains without reading the previous battle's mutable state")
	Campaign.pending = {}; Campaign.last_entry = {}
	check(Loop.unit(BattleFixture.loop(),"leonard")["permanent_gains"]==Permanent.empty(),"new campaign starts from source rather than prior acquired offsets")
	Campaign.clear_progress(PATH)
