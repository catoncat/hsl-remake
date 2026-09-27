extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleLoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")
const WeaponEffectRules = preload("res://game/sim/WeaponEffectRules.gd")
const run_weapon_effect_tests = preload("res://tests/run_weapon_effect_tests.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_permanent_items_tests = preload("res://tests/run_permanent_items_tests.gd")
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WIND := "magic:magicAIR:magicCode01"
const PATH := "res://content/battles/mobile_jobs_trial.json"
var draws: Array = []
var cursor := 0

func _init() -> void:
	tag = "MOBILE_JOBS_TESTS"

static func fresh() -> Dictionary:
	return BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file(PATH))

static func fixture(code: String="004", twice: bool=false, counter: bool=false) -> Dictionary:
	var loop := fresh()
	if not loop["scenario_ok"]: return loop
	var owner: Dictionary=loop["units"].filter(func(a):return a["actor_id"]==code)[0]
	var friend:=BattlePlayLoop.unit_ref(loop,"tina");var foe:=BattlePlayLoop.unit_ref(loop,"enemy026_1")
	owner.merge({"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"coord":Vector2i(14,16),"hit_bonus_accum":1000},true)
	owner["inventory"]=[108,102,227,232,241,244,253,0]
	if code in ["004","028"]: run_weapon_effect_tests.set_gear(owner,loop["equipment_items"],"weapon",108)
	if twice: run_weapon_effect_tests.set_gear(owner,loop["equipment_items"],"accessory2",227)
	owner["growth_profile"]["source"].merge({"hit_point":2000,"speed":300},true)
	foe.merge({"coord":Vector2i(15,16),"hit_bonus_accum":1000,"no_attack":not counter,"inventory":[0,0,0,0,0,0,0,0]},true)
	foe["growth_profile"]["source"].merge({"hit_point":5000,"magic_point":300,"attack_back":100,"speed":0},true)
	friend["coord"]=Vector2i(18,18);friend["growth_profile"]["source"]["speed"]=200
	loop["units"]=[owner,friend,foe]
	loop["player_unit_id"]=owner["id"]
	for actor in loop["units"]:
		actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		actor["hp"]=actor["max_hp"];actor["mp"]=actor["max_mp"];actor["ai_home_coord"]=actor["coord"]
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.return_to_player(loop,owner["id"])

func run() -> void:
	var loop:=fresh()
	check(loop["scenario_ok"],"complete public role initialization: "+str(loop.get("scenario_error")))
	if not loop["scenario_ok"]: return
	native_jobs(loop)
	native_mana()
	abilities_and_growth()
	series()
	cross_battle()
	await presentation()

func native_jobs(loop: Dictionary) -> void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_mobile_jobs.json"))
	for row in packet["cases"]:
		var c:Dictionary=row["input"]
		var actor:Dictionary=loop["units"].filter(func(a):return a["actor_id"]==c["actor"])[0].duplicate(true)
		actor["growth_profile"]=row["profile"].duplicate(true);actor["combat_profile"].merge(c["attributes"],true)
		actor["player_mode"]=int(row["profile"]["source"]["mode"]) # the mode_* cases ran with live +0x28 = this word
		actor.merge({"hp":int(c["hp"]),"mp":int(c["mp"]),"level":int(c["level"]),"base_move_point":int(c["base_move"]),"equipment":[]},true)
		for i in range(6):
			if c["equipment"][i]:actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[i],"item_code":int(c["equipment"][i])})
		for native in row["native"]:
			var error:=BattlePlayLoop.ProgressionRules.refresh_input_error(actor,loop["equipment_items"])
			check(error=="","native case validates: "+c["actor"]+"/"+c["name"]+" "+error)
			if error!="":continue
			actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
			var wanted:Dictionary=native["values"]
			for pair in [["max_hp","max_hp"],["max_mp","max_mp"],["hp","current_hp"],["mp","current_mp"],["move_point","move_point"],["live_speed","speed"]]:
				check(actor[pair[0]]==wanted[pair[1]],"source full refresh "+c["actor"]+" "+pair[0])
			for pair in [["live_attack_damage","attack"],["live_defense","defense"],["live_magic_attack","magic_attack"],["live_hit_ratio","hit_rate"],["avoid_hit_ratio","avoid_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"]]:
				check(actor["combat_profile"][pair[0]]==wanted[pair[1]],"source ordered profession math "+pair[0])
			for element in range(5):check(actor["combat_profile"]["resist_by_type"][str(element)]==wanted["resist_by_type"][str(element)],"source profession resistance "+str(element))
			check(BattlePlayLoop.ProgressionRules.exp_to_next(actor["level"])==wanted["exp_threshold"],"native refreshed growth threshold")

func native_mana() -> void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_mana_strike.json"))
	var initial:=fixture()
	for row in packet["caller"]:
		var c:Dictionary=row["input"];var loop:=initial.duplicate(true)
		var owner:=BattlePlayLoop.unit_ref(loop,"thief");var target:=BattlePlayLoop.unit_ref(loop,"enemy026_1")
		owner["id"]="0";target["id"]="1"
		own(loop, "equipment_items")["108"]["weapon_effect_flags"]=int(c["effects"])
		target["equipment"]=target["equipment"].filter(func(s):return s["slot"]!="accessory1")
		target["equipment"].append({"slot":"accessory1","item_code":229})
		own(loop, "equipment_items")["229"]["status_effect_flags"]=int(c["immunity"])
		target.merge({"hp":int(c["hp"]),"mp":int(c["mp"]),"status_flags":6|(1 if c["poison"] else 0),"status_counters":{"poison":int(c["poison"]),"paralysis":2,"no_magic":3}},true)
		var queue:={"index":int(c["index"]),"round":0,"slots":[]}
		for slot in c["slots"]:queue["slots"].append({"id":str(int(slot[0])),"enabled":bool(slot[1])})
		var prepared:=WeaponEffectRules.prepare(owner,target,loop["skill_book"],loop["equipment_items"],queue)
		check(prepared["ok"],"native MP target validates")
		if not prepared["ok"]:continue
		var enabled:bool=(int(c["remaining"])==0 or int(c["hp"])==0) and int(c["contribution"])>0
		draws=row["draws"].filter(func(r):return r["stage"]=="effects");cursor=0
		var before:=target.duplicate(true)
		var result:=WeaponEffectRules.resolve(prepared,replay,int(c["contribution"])) if enabled else {"changes":{},"queue":queue}
		var after:=target.duplicate(true);after.merge(result["changes"],true)
		check(after["mp"]==int(row["native"]["mp"]) and after["hp"]==int(row["native"]["hp"]),"original final-series MP loss and zero floor")
		check(after["status_counters"]["poison"]==int(row["native"]["poison"]) and after["status_counters"]["no_magic"]==3 and after["status_counters"]["paralysis"]==2,"combined weapon states preserve independent afflictions")
		check(target==before and cursor==draws.size(),"MP effect never consumes a new draw or mutates a proposal input")
		for i in range(queue["slots"].size()):check(result["queue"]["slots"][i]["enabled"]==bool(row["native"]["queue"][i]),"native cancellation remains before mana tail")

func abilities_and_growth() -> void:
	var loop:=fresh();var thief:=BattlePlayLoop.unit(loop,"thief");var wing:=BattlePlayLoop.unit(loop,"wing")
	check(thief["weapon_code"]==102 and thief["max_mp"]==0 and BattlePlayLoop.magic_options(loop,"thief").is_empty(),"source004 dagger and no magic are preserved")
	check(wing["weapon_code"]==43 and wing["traversal"]["flying"] and BattlePlayLoop.magic_options(loop,"wing").any(func(o):return o["id"]==WIND),"source006 spear, flight and Wind are available")
	check(not BattlePlayLoop.unit(loop,"enemy036_1")["traversal"]["flying"] and BattlePlayLoop.magic_options(loop,"enemy036_1").is_empty(),"same wing profession never grants absent036 flight or magic")
	check(BattlePlayLoop.unit(loop,"enemy028_1")["weapon_code"]==21 and BattlePlayLoop.unit(loop,"enemy036_1")["weapon_code"]==33,"foes retain their exact source equipment")
	# 004 declares 銀之手 (special_other) and 006 連續突刺 (special_other, magicCode16); both are
	# implemented from the PLAYERS declaration itself — never an unrelated replacement.
	check(BattlePlayLoop.special_options(loop,"thief").map(func(o):return o["id"])==["special:magicOTHER:magicCode10"] and BattlePlayLoop.special_options(loop,"wing").map(func(o):return o["id"])==["special:magicOTHER:magicCode16"],"declared initial specials are exactly 銀之手 (004) and 連續突刺 (006); no unrelated replacement")
	for code in ["004","006"]:
		var battle:=fixture(code);var id:=str(battle["selected_unit_id"]);var actor:=BattlePlayLoop.unit_ref(battle,id)
		actor["exp"]=99
		check(not BattleLoopInventory.resolve_item_use(battle,id,id,"253",6).is_empty(),"new source profession acquires permanent item through real commit")
		var gained:Dictionary=actor["permanent_gains"].duplicate(true)
		actor.merge(BattlePlayLoop.ProgressionRules.resolve_experience(actor,1,battle["equipment_items"]),true)
		var queue:Dictionary=battle["turn_queue"].duplicate(true)
		var allocated:=BattlePlayLoop.allocate_growth(battle,id,{"str":1,"dex":1,"mind":1,"con":2})
		check(BattlePlayLoop.unit(allocated,id)["level"]==2 and BattlePlayLoop.unit(allocated,id)["pending_stat_points"]==0 and allocated["turn_queue"]==queue,"manual profession allocation preserves action/queue")
		check(BattlePlayLoop.unit(allocated,id)["permanent_gains"]==gained,"new profession level refresh does not erase acquired source")
		var equipped:=BattlePlayLoop.change_equipment(allocated,"accessory2",2,227)
		var removed:=BattlePlayLoop.change_equipment(equipped,"accessory2",-1,0)
		check(BattlePlayLoop.unit(removed,id)["permanent_gains"]==gained and BattlePlayLoop.unit(removed,id)["combat_profile"]==BattlePlayLoop.unit(allocated,id)["combat_profile"],"equip/unequip cannot accumulate profession or permanent terms")
		check(BattleCheckpoint.encode(removed,run_permanent_items_tests.VIEW)["ok"],"new-role growth/item/equipment state serializes")
	var prohibited:=BattlePlayLoop.EquipmentRules.replace(wing,"weapon",0,108,loop["equipment_items"])
	check(not prohibited["ok"] and prohibited["reason"]=="wrong_job","wing cannot borrow Thief-only mana weapon")
	var mobile:=fixture("006",true)
	mobile=BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(mobile,"move"),Vector2i(13,16))
	check(not BattlePlayLoop.command_available(mobile,"magic"),"source flight does not imply moved casting")
	var rolled_back:=BattlePlayLoop.cancel_interaction(BattlePlayLoop.cancel_pending_move(mobile))
	check(BattlePlayLoop.command_available(rolled_back,"magic"),"movement cancellation restores original casting qualification")
	var granted:=BattlePlayLoop.change_equipment(mobile,"accessory1",3,232)
	check(BattlePlayLoop.command_available(granted,"magic"),"actual movement ring enables already accepted destination")

func series() -> void:
	for count in [1,2]:
		var loop:=fixture("004",true)
		own(loop, "skill_book")["actors"]["004"]["double_attack"]=count==2
		var result:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),"enemy026_1",zero)
		check(not result["last_attack"].is_empty(),"native mana ordinary attack commits")
		if result["last_attack"].is_empty():continue
		var strikes:Array=[result["last_attack"]];strikes.append_array(result["last_attack"].get("followups",[]))
		check(strikes.size()==count,"requested series strike count")
		for i in range(strikes.size()):
			var s:Dictionary=strikes[i]
			check(s.has("weapon_effects")== (i==count-1),"mana applies once at final blow")
			if s.has("weapon_effects"):
				check(int(s["weapon_effects"]["mana"]["loss"])==mini(int(s["defender_before"]["mp"]),int(s["native_contribution"])/3),"mana uses this blow HP cap, not total or EXP")
		check(BattlePlayLoop.unit(result,"thief")["mp"]==0 and not result["extra_action"]["pending"],"attack gives no caster mana and presentation precedes next action")
		result=BattlePlayLoop.finish_exhausted_action(result)
		check(result["extra_action"]["pending"] and BattleCheckpoint.encode(result,run_permanent_items_tests.VIEW)["ok"],"finished series enables independently saved second action")
		var again:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(result,"attack"),"enemy026_1",zero)
		again=BattlePlayLoop.finish_exhausted_action(again)
		check(again["action_end_sequence"]==1 and not again["extra_action"]["pending"],"two accepted series execute just one final status tail")
	for hp in [1,3,7]:
		var lethal:=fixture();own(lethal, "skill_book")["actors"]["004"]["double_attack"]=true
		BattlePlayLoop.unit_ref(lethal,"enemy026_1")["hp"]=hp
		var hit:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(lethal,"attack"),"enemy026_1",zero)
		var s:Dictionary=hit["last_attack"]
		check(s["followups"].is_empty() and int(s["weapon_effects"]["mana"]["loss"])==hp/3,"first lethal skips second and uses capped HP: "+str(hp))
	var missed:=fixture();BattlePlayLoop.unit_ref(missed,"thief")["hit_bonus_accum"]=0
	BattlePlayLoop.unit_ref(missed,"thief")["combat_profile"]["live_hit_ratio"]=0 # Explicit low-accuracy final-miss fixture.
	var first:=BattleLoopCombat.apply_strike(missed,"thief","enemy026_1",zero,false,1)
	var before_mp:=int(BattlePlayLoop.unit(missed,"enemy026_1")["mp"])
	var last:=BattleLoopCombat.apply_strike(missed,"thief","enemy026_1",high,false,0)
	check(not first.has("weapon_effects") and not last["hit"] and not last.has("weapon_effects") and BattlePlayLoop.unit(missed,"enemy026_1")["mp"]==before_mp,"final miss cannot borrow earlier HP contribution for mana")
	var counter:=fixture("006",false,true)
	var defender:=BattlePlayLoop.unit_ref(counter,"enemy026_1")
	# Explicit ability source fixture: the opposite actor carries the same MP bit.
	own(counter, "equipment_items")[str(int(defender["weapon_code"]))]["weapon_effect_flags"]=WeaponEffectRules.MANA
	own(counter, "skill_book")["actors"]["026"]["double_attack"]=true
	var returned:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(counter,"attack"),"enemy026_1",zero)
	var counters:Dictionary=returned["last_attack"].get("counter",{})
	check(not counters.is_empty() and not counters.has("weapon_effects") and counters["followups"][0]["weapon_effects"].has("mana"),"counter series uses its own final mana tail")

func cross_battle() -> void:
	var destination:=fresh()
	var untouched:=destination.duplicate(true)
	for code in ["004","006"]:
		var battle:=fixture(code,true)
		var id:=str(battle["player_unit_id"])
		var actor:=BattlePlayLoop.unit_ref(battle,id)
		check(not BattleLoopInventory.resolve_item_use(battle,id,id,"253",6).is_empty(),"new profession permanently gains through production item commit")
		actor["exp"]=99;BattlePlayLoop.unit_ref(battle,"enemy026_1")["hp"]=1
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,5)["changes"],true)
		battle=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(battle,"attack"),"enemy026_1",zero)
		check(battle["battle_outcome"]==BattleOutcome.VICTORY_ENEMIES_CLEARED and BattlePlayLoop.unit(battle,id)["level"]==2,"new profession carries actual final kill/EXP result")
		var carry:=CampaignProgress.CarryRules.capture(battle)
		var path:String="res://ignored/mobile-jobs/carry-"+str(code)+".json"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		check(CampaignProgress.save_progress({"scenario_path":PATH,"carry":carry},path),"new profession writes isolated campaign JSON")
		var saved:=CampaignProgress.load_progress(path)
		var incoming:=BattlePlayLoop.apply_campaign_carry(destination,saved["carry"])
		check(incoming["campaign_carry_receipt"]["errors"].is_empty() and destination==untouched,"new battle applies role identity without mutating its input")
		var owner:=BattlePlayLoop.unit(incoming,id);var old:=BattlePlayLoop.unit(battle,id)
		for key in ["level","exp","pending_stat_points","weapon_code","permanent_gains"]:
			check(owner[key]==old[key],"new profession keeps persisted source field: "+key)
		# Campaign JSON decodes numeric entries as floats. Compare validated item
		# identities and slot order, not the pre-serialization Variant number type.
		check(owner["inventory"].map(func(v):return int(v))==old["inventory"].map(func(v):return int(v)),"campaign keeps every inventory slot and item code")
		check(owner["equipment"].map(func(s):return [str(s["slot"]),int(s["item_code"])])==old["equipment"].map(func(s):return [str(s["slot"]),int(s["item_code"])]),"campaign keeps every equipped source and slot")
		check(owner["growth_profile"]==BattlePlayLoop.unit(destination,id)["growth_profile"] and owner["status_flags"]==0,"carry keeps destination source job and discards old temporary poison")
		check(owner["hp"]==owner["max_hp"] and owner["mp"]==owner["max_mp"],"carried resources use newly derived source maxima")
		check(incoming["item_use_sequence"]==0 and incoming.get("last_combat",{}).is_empty(),"new battle cannot replay permanent item or last MP strike")
		check(BattlePlayLoop.apply_campaign_carry(incoming,saved["carry"])["units"]==incoming["units"],"reusing entry record replaces acquired values without accumulating")
		var active:=BattlePlayLoop.begin_battle(incoming)
		var encoded:=BattleCheckpoint.encode(active,run_permanent_items_tests.VIEW)
		check(encoded["ok"],"carried six-job source accepts a quiet checkpoint")
		if encoded["ok"]:
			var restored:=BattleCheckpoint.decode(encoded["bytes"], active)
			check(restored["ok"] and restored["snapshot"]["loop"]==active,"carried six-job source and saved queue round-trip unchanged")
		check(BattlePlayLoop.apply_campaign_carry(active,saved["carry"])==active,"late carry cannot alter an active second/first action")
		CampaignProgress.clear_progress(path)

func presentation() -> void:
	var loop:=fixture();own(loop, "skill_book")["actors"]["004"]["double_attack"]=true
	var result:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),"enemy026_1",zero)
	var view=preload("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(view);view.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json");view.set_process(false)
	var first:Dictionary=result["last_attack"];var final:Dictionary=first["followups"][0]
	# The fixture's no_attack only suppresses the counter; the strip would mask a no_attack unit's MP (0x434d10 bVar21).
	var target:Dictionary=BattlePlayLoop.unit(result,"enemy026_1");target.erase("no_attack")
	for strike in [first,final]:
		view.play(strike,BattlePlayLoop.unit(result,"thief"),target,false)
		var clip:Dictionary=view.clips.back()
		view._show_shot(clip,true)
		check(view.vitals.values["mp"].text.begins_with(str(int(strike["defender_before"]["mp"]))),"committed future mana loss is hidden before this blow")
		clip["impact_emitted"]=true;view._show_shot(clip,true)
		check(view.vitals.values["mp"].text.begins_with(str(int(strike["defender_after"]["mp"]))),"impact shows only that blow's actual remaining MP")
		view.clips.clear()
	view.queue_free();await process_frame

func replay(bound:int)->int:
	check(cursor<draws.size(),"bounded replay has no extra mana draws")
	if cursor>=draws.size():return 0
	var row:Dictionary=draws[cursor];cursor+=1
	check(bound==int(row["bound"]),"native effect random order remains stable")
	return int(row["value"])
