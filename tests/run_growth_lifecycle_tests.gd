extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const LearningRules = preload("res://game/sim/LearningRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const run_entry_growth_tests = preload("res://tests/run_entry_growth_tests.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const JobUpRules = preload("res://game/sim/JobUpRules.gd")
const run_job_stats_tests = preload("res://tests/run_job_stats_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const HEAL := "magic:magicWATER:magicCode06"
const CURE := "magic:magicWATER:magicCode05"
const FLAME_WAVE := "magic:magicFIRE:magicCode06" # 赤炎波動: job86 神官長 threshold 26 (0x4373f0 case 0x4374c2)
const THUNDER_BLADE := "special:magicAIR:magicCode01" # 天雷猛襲劍: warrior table row tier1
const RAIN_SLASH := "special:magicWATER:magicCode01" # 慌雨斬: warrior table row tier2, reached by job81 劍豪
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
var checks := 0
var failures: Array[String] = []
var templates := {}


func _initialize() -> void: call_deferred("run")


static func fixture(level: int = 5, extra: bool = true) -> Dictionary:
	var loop := run_support_magic_tests.priest_fixture()
	var actor := BattlePlayLoop.unit_ref(loop, "tina")
	var ally := BattlePlayLoop.unit_ref(loop, "companion")
	var enemy := BattlePlayLoop.unit_ref(loop, "enemy021_1")
	actor["level"] = level; actor["exp"] = BattlePlayLoop.ProgressionRules.exp_to_next(level)-1
	actor["growth_profile"]["source"].merge({"hit_point":400,"magic_point":200,"speed":200}, true)
	actor["inventory"] = [232,227,244,247,241,253,0,0]
	if extra:
		actor["equipment"] = actor["equipment"].filter(func(s):return s["slot"] != "accessory2")
		# The runtime's equipment entry shape (EquipmentRules.replace: slot, item_code, name); the carry seam validates it against content/schema/unit.schema.json.
		actor["equipment"].append({"slot":"accessory2","item_code":227,"name":str(loop["equipment_items"]["227"]["name"])})
	ally["growth_profile"]["source"].merge({"hit_point":500,"speed":150}, true)
	ally["hp"] = 10
	enemy["growth_profile"]["source"].merge({"hit_point":800,"speed":0}, true)
	enemy["no_attack"] = true; enemy["inventory"] = [0,0,0,0,0,0,0,0]
	for unit in loop["units"]:
		unit.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(unit,loop["equipment_items"]),true)
		if unit != ally: unit["hp"] = unit["max_hp"]
		unit["mp"] = unit["max_mp"]
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.return_to_player(loop,"tina")


static func cast(loop: Dictionary, id: String = HEAL, target: String = "companion", rng: Variant = null) -> Dictionary:
	return BattlePlayLoop.attack_target(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop,"magic"),id),target,rng)


func run() -> void:
	create_timer(180).timeout.connect(func():push_error("GROWTH_LIFECYCLE_TIMEOUT");quit(2))
	for path in ["res://content/battles/first_battle.json",run_mobile_jobs_tests.PATH,"res://content/battles/large_actor_trial.json"]:
		var created := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file(path))
		check(created["scenario_ok"],"source templates initialize: "+path)
		for actor in created["units"]: templates[actor["actor_id"]] = actor.duplicate(true)
	native_rewards()
	native_learning()
	actual_acquisition()
	job_up_learning()
	initial_rosters()
	await separate_party_stream()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("GROWTH_LIFECYCLE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	call_deferred("quit",0 if failures.is_empty() else 1)


func separate_party_stream() -> void:
	# The real level53 runtime skips Leonard's party. Its opening births draw the process's
	# global stream (never carried, as the original keeps 0x4795d4 out of its save).
	var previous_pending := CampaignProgress.pending.duplicate(true)
	var previous_entry := CampaignProgress.last_entry.duplicate(true)
	var origin := BattlePlayLoop.initialize_roster_growth(BattleFixture.loop())
	BattlePlayLoop.unit_ref(origin,"leonard")["permanent_gains"]["attack_power"] = 7
	origin["gold"] = 777
	var carried := BattlePlayLoop.CampaignCarryRules.capture(origin)
	var entry := {"schema":CampaignProgress.SCHEMA,"scenario_path":"res://content/battles/battle_053.json","carry":carried}
	CampaignProgress.pending=entry.duplicate(true);CampaignProgress.last_entry={}
	var scene=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.startup_mode="dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	check(scene.play_loop["scenario_ok"],"real separate-party runtime starts")
	check(TestSuite.carries_no_stream(carried),"separate party's opening births start from the process's global stream, not from a carried one")
	check(GlobalRandomStream.session()==TestSuite.stream_of(scene.play_loop, "global"),"the process stream follows the battle's global words")
	check(scene.play_loop.get("campaign_carry_receipt",{}).get("applied_unit_ids",[]).is_empty() and scene.play_loop["gold"]!=777,"separate party never receives Leonard's records or wallet")
	check(BattlePlayLoop.unit(scene.play_loop,"tina")["permanent_gains"]["attack_power"]==0,"separate source002 does not inherit source001 permanent gains")
	var outgoing:Dictionary=scene.campaign_progress.prepare_handoff()
	check(not outgoing.is_empty() and outgoing["carry"]["units"]==carried["units"] and outgoing["carry"]["loop"]==carried["loop"],"separate battle passes the original party unchanged")
	check(TestSuite.carries_no_stream(outgoing["carry"]),"outgoing handoff carries no global stream")
	root.remove_child(scene);scene.queue_free()
	await process_frame
	var retry=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	retry.startup_mode="dev_first_control"
	root.add_child(retry)
	await process_frame
	retry.set_process(false)
	root.remove_child(retry);retry.queue_free()
	await process_frame
	CampaignProgress.pending=previous_pending;CampaignProgress.last_entry=previous_entry


func native_rewards() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_growth_lifecycle.json"))
	var equipment: Dictionary = BattleFixture.loop()["equipment_items"]
	for row in packet["rewards"]:
		var c: Dictionary = row["input"]
		var actor: Dictionary = templates[c["actor"]].duplicate(true)
		actor["growth_profile"]["allocation"] = "automatic" if int(c["object_kind"]) != 3 else "manual"
		actor["player_mode"] = int(c["mode"]) # live +0x28 of the native run (0x448840 hp_level term)
		actor.merge({"level":int(c["level"]),"exp":int(c["exp"]),"hp":int(c["hp"]),"mp":int(c["mp"]),"base_move_point":int(c["base_move"]),"equipment":[],"pending_stat_points":0},true)
		actor["combat_profile"].merge(c["attributes"],true)
		for i in range(6):
			if int(c["equipment"][i]) > 0: actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[i],"item_code":int(c["equipment"][i])})
		actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,equipment)
		var before:=actor.duplicate(true)
		var grown:=BattlePlayLoop.ProgressionRules.apply_level_ups(actor,equipment)
		check(actor==before,"growth proposal preserves caller state")
		if int(c["object_kind"])==3:
			check(grown["combat_profile"]["str"]==before["combat_profile"]["str"] and (int(grown["pending_stat_points"])>0)==bool(row["native"]["manual_ui"]),"manual branch reserves points and never auto-assigns")
			continue
		for key in ["level","exp","max_hp","max_mp"]:check(grown[key]==row["native"][key],"full native reward allocation "+key)
		for key in LearningRules.ATTRIBUTES:check(grown["combat_profile"][key]==row["native"]["attributes"][key],"native quota/cap fallback "+key)
		for pair in [["hp","current_hp"],["mp","current_mp"],["live_speed","speed"]]:check(grown[pair[0]]==row["native"][pair[1]],"NPC growth clamps without filling "+pair[0])
		check(grown["pending_stat_points"]==0 and grown.get("learned_skills",[]).is_empty(),"NPC auto allocation neither reserves manual points nor learns player spells")


func native_learning() -> void:
	var loop:=BattleFixture.loop();var book:Dictionary=loop["skill_book"].duplicate(true)
	var data:Dictionary=book["learning"]
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_growth_lifecycle.json"))
	for row in packet["learning"]:
		var c:Dictionary=row["input"]
		var actor:Dictionary=templates[{80:"001",85:"002",88:"004",90:"026",92:"006",94:"039"}[int(c["job"])]].duplicate(true)
		actor["growth_profile"]["allocation"]="manual"
		actor["level"]=int(c["level"])+1 if c["kind"]=="magic" else int(c["level"])
		for i in range(4):actor["combat_profile"][LearningRules.ATTRIBUTES[i]]=int(c["attributes"][i])
		data["actors"][actor["actor_id"]]={}
		book["actors"][actor["actor_id"]]["supported_initial_ids"]=[]
		if c["existing"]:
			for kind in ["magicEARTH","magicWATER","magicAIR","magicFIRE","magicMIND","magicOTHER","magicOTHER2"]:data["actors"][actor["actor_id"]][c["kind"]+":"+kind]=0xffffffff
		var result:=LearningRules.acquire(actor,book,c["kind"])
		var masks:Array=[]
		for _i in range(6 if c["kind"]=="magic" else 7):masks.append(0xffffffff if c["existing"] else 0)
		for learned in result["actor"].get("learned_skills",[]):
			var parts:PackedStringArray=learned["id"].split(":")
			var index:=["magicEARTH","magicWATER","magicAIR","magicFIRE","magicMIND","magicOTHER","magicOTHER2"].find(parts[1])
			masks[index]=int(masks[index]) | (1<<(parts[2].trim_prefix("magicCode").to_int()-1))
		if c["kind"]=="special" and c["preview"]:
			check(row["native"]["masks"].all(func(v):return int(v)==0) and result["added"].size()<=1,"native special preview remains separate from a committed acquisition")
		else:check(masks==row["native"]["masks"].map(func(v):return int(v)),"exact original learning mask at threshold, below threshold and repeated ownership: "+str(c))
		check(LearningRules.input_error(result["actor"],data)=="","acquisition validates its exact stored source and triggering attributes")


func actual_acquisition() -> void:
	var loop:=fixture()
	var actor:=BattlePlayLoop.unit(loop,"tina")
	check(BattlePlayLoop.SkillResolutionRules.ownership_error(actor,CURE,loop["skill_book"])=="skill_not_owned","priest cannot use cure before earned level")
	var before:=loop.duplicate(true)
	var learned:=cast(loop,HEAL,"companion",zero)
	check(loop==before and BattlePlayLoop.unit(learned,"tina")["level"]==6,"real paid healing crosses a level without mutating previous state")
	check(BattlePlayLoop.SkillResolutionRules.ownership_error(BattlePlayLoop.unit(learned,"tina"),CURE,learned["skill_book"])=="","new level grants exact cure spell before the next independent action")
	check(learned["last_attack"]["experience"]["learning"].has("習得 驅毒"),"new skill has a committed aftermath label")
	learned=BattlePlayLoop.finish_exhausted_action(learned)
	var party:=BattlePlayLoop.unit_ref(learned,"companion")
	party.merge(BattlePlayLoop.StatusEffectRules.apply(party,"poison",3,8)["changes"],true)
	var healed:=BattlePlayLoop.finish_exhausted_action(cast(learned,CURE,"companion",zero))
	check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(healed,"companion")),"newly learned cure is used in the second action: "+str({"phase":learned["interaction"],"selected":learned["selected_unit_id"] ,"extra":learned["extra_action"],"reject":healed.get("last_attack_reject"),"options":BattlePlayLoop.magic_options(learned,"tina")}))
	check(healed["action_end_sequence"]==1 and not healed["extra_action"]["pending"],"two independent actions close a single resource/status tail")
	for item in [learned,healed]:
		var encoded:=BattleCheckpoint.encode(item,VIEW)
		check(encoded["ok"],"learned state and receipt can be saved: "+str(encoded.get("reason")))
		if encoded["ok"]:check(BattleCheckpoint.decode(encoded["bytes"], item)["snapshot"]["loop"]==item,"restoring does not grant again or draw randomness")
	var broken:=learned.duplicate(true)
	BattlePlayLoop.unit_ref(broken,"tina")["learned_skills"][0]["level"]=1
	check(not BattleCheckpoint.encode(broken,VIEW)["ok"],"unearned/edited acquisition is rejected")
	var rng_before:Array=TestSuite.stream_of(learned, "global").duplicate()
	var stats:=BattlePlayLoop.unit_ref(learned,"tina")
	var records:Array=stats["learned_skills"].duplicate(true)
	stats["permanent_gains"]["magic_attack_power"]=8
	stats.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(stats,learned["equipment_items"]),true)
	check(stats["learned_skills"]==records and TestSuite.stream_of(learned, "global")==rng_before,"permanent/equipment/temporary refresh leaves learned masks and the global stream alone")
	var no_points:=BattlePlayLoop.allocate_growth(learned,"tina",{})
	check(no_points==learned,"cancelled empty point draft cannot learn a special")
	for status in ["no_magic","paralysis"]:
		var blocked:=learned.duplicate(true);var source:=BattlePlayLoop.unit_ref(blocked,"tina")
		source.merge(BattlePlayLoop.StatusEffectRules.apply(source,status,2)["changes"],true)
		var result:=BattlePlayLoop.SkillResolutionRules.available(source,CURE,BattlePlayLoop.skill_fields(blocked,CURE),blocked["skill_book"],blocked["skill_target_data"],blocked["equipment_items"])
		check(not result["ok"] and source["learned_skills"]==records,"status restricts actual use without deleting learned ability")
	var npc:=fixture();var caster:=BattlePlayLoop.unit_ref(npc,"tina")
	caster["growth_profile"]["allocation"]="automatic"
	var auto:=cast(npc,HEAL,"companion",zero)
	check(BattlePlayLoop.unit(auto,"tina")["level"]==6 and BattlePlayLoop.unit(auto,"tina")["pending_stat_points"]==0 and not LearningRules.owns(BattlePlayLoop.unit(auto,"tina"),CURE),"NPC crosses the same experience threshold through quota assignment without player learning")
	var entered:=run_entry_growth_tests.fixture("026",[20,3],16)
	BattleLoopScript.maintain_script_pressure(entered)
	var recruit:Dictionary=run_entry_growth_tests.created(entered)[0]
	recruit["growth_profile"]["allocation"]="automatic"
	var birth:Dictionary=recruit["entry_growth"].duplicate(true)
	var grown:=BattlePlayLoop.ProgressionRules.resolve_experience(recruit,BattlePlayLoop.ProgressionRules.exp_to_next(recruit["level"]),entered["equipment_items"])
	check(grown["entry_growth"]==birth and BattlePlayLoop.ReinforcementGrowth.Entry.input_error(grown)=="","NPC post-birth growth does not replay random source bonuses")


func job_up_learning() -> void:
	# After a 命運神殿 job-up the member's current job code selects the learning
	# table (0x4373f0 / 0x437a40 dispatch on actor+0x18); records learned under the
	# previous job stay under that job. The same member without the job-up is the control.
	var loop := fixture(25)
	var tina := BattlePlayLoop.unit_ref(loop, "tina")
	var merged := JobUpRules.merge_source_template(tina, JobUpRules.load_source_template("011"), JobUpRules.NATIVE_JOB_UP_FLAG)
	check(merged["ok"] and int(merged["actor"]["growth_profile"]["job_code"]) == 86, "011 template turns 祭司 into 神官長 86")
	tina.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(merged["actor"], loop["equipment_items"]), true)
	tina["hp"] = tina["max_hp"]; tina["mp"] = tina["max_mp"]
	var learned := cast(loop, HEAL, "companion", zero)
	var grown := BattlePlayLoop.unit(learned, "tina")
	check(grown["level"] == 26 and LearningRules.owns(grown, FLAME_WAVE), "job-up member crossing level 26 learns 赤炎波動 from the job86 table")
	var flame: Array = grown.get("learned_skills", []).filter(func(row): return row["id"] == FLAME_WAVE)
	check(flame.size() == 1 and int(flame[0]["job"]) == 86 and flame[0]["trigger"] == "level_up", "acquisition is recorded under the current job 86")
	check(LearningRules.input_error(grown, learned["skill_book"]["learning"]) == "" and learned["last_attack"]["experience"]["learning"].has("習得 赤炎波動") and not learned["last_attack"]["experience"]["learning"].has("習得 赤炎波動（尚未可用）"), "job-up acquisition validates and is announced as available (赤炎波動 is castable since the wave-9 skill coverage)")
	var encoded := BattleCheckpoint.encode(learned, VIEW)
	check(encoded["ok"] and BattleCheckpoint.decode(encoded["bytes"], learned)["snapshot"]["loop"] == learned, "job-up learning state saves and restores exactly")
	var control := BattlePlayLoop.unit(cast(fixture(25), HEAL, "companion", zero), "tina")
	check(control["level"] == 26 and not LearningRules.owns(control, FLAME_WAVE) and LearningRules.owns(control, "magic:magicMIND:magicCode03"), "祭司 at the same level keeps the job85 table: 咒靈縛剎 yes, 赤炎波動 no")
	for upgraded in [false, true]:
		var battle := run_job_stats_tests.fixture("001")
		var leonard := BattlePlayLoop.unit_ref(battle, "leonard")
		for key in LearningRules.ATTRIBUTES: leonard["combat_profile"][key] = {"str": 26, "dex": 20, "mind": 20, "con": 24}[key]
		leonard.merge(LearningRules.acquire(leonard, battle["skill_book"], "special")["actor"], true)
		check(LearningRules.owns(leonard, THUNDER_BLADE) and int(leonard["learned_skills"][0]["job"]) == 80, "劍士 tier1 special learned before the job-up")
		if upgraded:
			leonard.merge(JobUpRules.merge_source_template(leonard, JobUpRules.load_source_template("010"), JobUpRules.NATIVE_JOB_UP_FLAG)["actor"], true)
		for key in LearningRules.ATTRIBUTES: leonard["combat_profile"][key] = {"str": 39, "dex": 32, "mind": 26, "con": 40}[key]
		leonard["pending_stat_points"] = 5
		leonard.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(leonard, battle["equipment_items"]), true)
		var allocated := BattlePlayLoop.allocate_growth(battle, "leonard", {"str": 1})
		var actor := BattlePlayLoop.unit(allocated, "leonard")
		check(actor["combat_profile"]["str"] == 40 and actor["pending_stat_points"] == 4, "real point allocation applies for job %d" % int(actor["growth_profile"]["job_code"]))
		check(LearningRules.owns(actor, RAIN_SLASH) == upgraded, "tier2 慌雨斬 is learned only through the 劍豪 tier (upgraded=%s)" % upgraded)
		if upgraded:
			var rain: Array = actor["learned_skills"].filter(func(row): return row["id"] == RAIN_SLASH)
			check(rain.size() == 1 and int(rain[0]["job"]) == 81 and int(actor["learned_skills"][0]["job"]) == 80, "new special is recorded under job 81 while the job80 record stays")
		check(LearningRules.input_error(actor, allocated["skill_book"]["learning"]) == "" and BattleCheckpoint.encode(allocated, VIEW)["ok"], "mixed-job records validate and save")


func initial_rosters() -> void:
	for path in ["res://content/battles/first_battle.json","res://content/battles/battle_052.json","res://content/battles/battle_053.json",run_mobile_jobs_tests.PATH,"res://content/battles/large_actor_trial.json"]:
		var source:=BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file(path));var before:=source.duplicate(true)
		var start:=BattlePlayLoop.initialize_roster_growth(source)
		check(start["scenario_ok"],"complete real initial roster: "+path+" "+str(start.get("scenario_error")))
		if not start["scenario_ok"]:continue
		check(source==before and BattlePlayLoop.initialize_roster_growth(start)==start,"initial roster growth is immutable and idempotent")
		check(BattlePlayLoop.ReinforcementGrowth.state_error(start)=="" and BattlePlayLoop.InitialRosterGrowth.state_error(start)=="","initial and later birth RNG validators agree")
		for actor in start["units"]:
			check(actor["hp"]==actor["max_hp"] and actor["mp"]==actor["max_mp"],"first creation fills resources only once")
			if actor["growth_profile"]["allocation"]=="automatic":check(actor["entry_growth"]["origin"]=="initial_roster","NPC created through full source birth proposal")
		var live:=BattlePlayLoop.begin_battle(start);var encoded:=BattleCheckpoint.encode(live,VIEW)
		check(encoded["ok"],"initially adjusted live roster saves: "+str(encoded.get("reason")))
		if encoded["ok"]:check(BattleCheckpoint.decode(encoded["bytes"], live)["snapshot"]["loop"]==live,"initial F9 cannot resample birth or remake the queue")


func zero(_bound:int)->int:return 0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
