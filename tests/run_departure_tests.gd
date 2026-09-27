extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleLoopInventory = preload("res://game/sim/loop/BattleLoopInventory.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const run_large_actor_tests = preload("res://tests/run_large_actor_tests.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}


func _init() -> void:
	tag = "DEPARTURE_TESTS"


static func fixture(twice:bool=false)->Dictionary:
	var loop:=run_mobile_jobs_tests.fixture("004",twice)
	var actor:=BattlePlayLoop._unit(loop,"thief")
	var friend:=BattlePlayLoop._unit(loop,"tina")
	friend["coord"]=Vector2i(14,15);friend["grid_coord"]=friend["coord"];friend["ai_home_coord"]=friend["coord"]
	for status in ["poison","no_magic"]:actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,status,3,7 if status=="poison" else 0)["changes"],true)
	loop["objective_phase"]="hold"
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop._return_to_player(loop,"thief")

static func living_enemies(loop:Dictionary)->int:
	return loop["units"].filter(func(actor):return actor["battle_actor_role"]=="enemy_ai" and BattlePresenceRules.living(actor)).size()

static func request(loop:Dictionary,ids:Array,key:String="event_departure")->Dictionary:
	var next:=loop.duplicate(true)
	if not next.has("winfail_runtime"):next["winfail_runtime"]={"fired":[],"departed_unit_ids":[],"departure_requests":[]}
	var runtime:Dictionary=next["winfail_runtime"]
	if not runtime.has("departure_requests"):runtime["departure_requests"]=[]
	runtime["fired"].append({"key":key,"turn":next["turn"],"context":"test"})
	for id in ids:
		if BattlePresenceRules.living(BattlePlayLoop.unit(next,id)) and not runtime["departed_unit_ids"].has(id):runtime["departed_unit_ids"].append(id)
	runtime["departure_requests"].append({"key":key,"name":"actDeleteObject","unit_ids":ids.duplicate(),"firing_index":runtime["fired"].size()-1})
	return BattlePlayLoop._resolve_outcome(next)

func run()->void:
	native_queue()
	current_and_future()
	spatial_and_targets()
	transactions_and_endings()
	checkpoint()
	script_configuration()
	ai_script_handoff()
	rearmed_binding()

func native_queue()->void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_script_departure.json"))
	for row in packet["phases"]:
		var c:Dictionary=row["input"]
		if c["sub"] not in [1,8] or c["ticks"]!=1:continue
		var loop:=fixture()
		loop["turn_queue"]["index"]=1 if c["current"] else 0
		var prepared:=BattlePresenceRules.prepare(loop,["tina"],"winfail","native_phase")
		check(prepared["ok"] and prepared["changed"],"native phase cleanup accepts a present target")
		var q:Dictionary=prepared["queue"]
		check(BattlePlayLoop.CoreTurnQueue.current(q)["id"]==("enemy026_1" if c["current"] else "thief"),"native current-removal successor matches compact queue semantics")
		check(q["slots"].all(func(s):return s["id"]!="tina") and q["round"]==loop["turn_queue"]["round"],"native queue unregister removes exactly one actor without ticking others")
		check(row["native"]["vitals_unchanged"],"native full actor data after header remains unchanged")

func current_and_future()->void:
	for current in ["thief","tina","enemy026_1"]:
		for removed in ["thief","tina","enemy026_1"]:
			var base:=fixture(true)
			base["turn_queue"]["index"]=base["turn_queue"]["slots"].map(func(s):return s["id"]).find(current)
			base["selected_unit_id"]=current if current!="enemy026_1" else ""
			base["interaction"]="action_menu" if current!="enemy026_1" else "ai_resolving"
			var before:=base.duplicate(true)
			var next:=request(base,[removed])
			var actor:=BattlePlayLoop.unit(next,removed)
			check(base==before and next["scenario_ok"],"departure is an immutable valid proposal")
			check(actor["departed"] and not actor["defeated"] and actor["hp"]>0,"departure is not a death")
			for key in ["hp","mp","stamina","exp","level","kill_count","kill_chain_word","inventory","equipment","permanent_gains","status_flags","status_counters","combat_profile"]:
				check(actor[key]==BattlePlayLoop.unit(base,removed)[key],"departure preserves historical field "+key)
			for key in ["gold",STREAM_KEYS["reward"],STREAM_KEYS["damage"],"item_use_sequence","action_end_sequence","rewarded_unit_ids"]:
				check(next[key]==base[key],"departure does not pay/tick/award "+key)
			check(BattlePresenceRules.state_error(next)=="","departure ledger/queue/flags are coherent")
			if current!=removed:check(BattlePlayLoop.CoreTurnQueue.current(next["turn_queue"])["id"]==current,"removing another slot preserves current actor")
			check(request(next,[removed])["units"]==next["units"] and next["departure_sequence"]==1,"repeat request does not reapply state")
	var second:=BattlePlayLoop.choose_command(fixture(true),"wait")
	check(second["extra_action"]["pending"],"fixture has a genuine second action")
	var gone:=request(second,["thief"])
	check(gone["selected_unit_id"]=="tina" and not gone["extra_action"]["pending"] and gone["action_end_sequence"]==second["action_end_sequence"],"departure during second action discards repeat eligibility without status/regen tail")
	var waiting:=fixture()
	waiting["winfail_runtime"]={"fired":[{"key":"event_wait"}],"departed_unit_ids":["thief"],"departure_requests":[{"key":"event_wait","unit_ids":["thief"],"firing_index":0}]}
	var handed:=BattlePlayLoop.begin_wait_resolution(waiting)
	check(handed["selected_unit_id"]=="tina" and handed["action_end_sequence"]==0 and not handed["attacked_this_action"],"resolving a departure at wait does not spend the new actor")
	var q:Dictionary=BattlePlayLoop.CoreTurnQueue.cancel_pending(fixture()["turn_queue"],"tina")["queue"]
	var removed:=BattlePlayLoop.CoreTurnQueue.remove_actors(q,["thief"],BattlePlayLoop._queue_actors(fixture()))
	check(BattlePlayLoop.CoreTurnQueue.current(removed["queue"])["id"]=="enemy026_1" and not removed["queue"]["slots"][0]["enabled"],"current removal respects a previously cancelled successor")
	var no_one:=request(fixture(),["thief","tina","enemy026_1"])
	check(no_one["turn_queue"]["slots"].is_empty() and BattlePlayLoop.CoreTurnQueue.current(no_one["turn_queue"])["id"]=="","all departures produce an empty queue, not a rebuilt ghost")
	check(BattlePlayLoop.step_ai_turn(no_one)==no_one,"empty departure state is stable")

func spatial_and_targets()->void:
	var base:=run_large_actor_tests.fixture(false)
	var giant:=BattlePlayLoop.unit(base,"enemy039_1")
	var occupied:=BattlePlayLoop.TraversalRules.prepare(BattlePlayLoop.unit(base,"leonard"),base["units"],base["tiles"])
	for point in BattlePlayLoop.Footprint.cells(giant):check(occupied["occupied"].has(point),"all nine body cells initially occupied")
	var next:=request(base,["enemy039_1"])
	var released:=BattlePlayLoop.TraversalRules.prepare(BattlePlayLoop.unit(next,"leonard"),next["units"],next["tiles"])
	for point in BattlePlayLoop.Footprint.cells(giant):
		check(not released["occupied"].has(point) and BattlePlayLoop.unit_id_at_coord(next,point)=="","all nine body cells release and cannot be selected")
	check(BattlePlayLoop.attack_cells(next,"enemy039_1").is_empty() and BattlePlayLoop.movement_cells(next,"enemy039_1").is_empty(),"departed body cannot initiate targeting or movement")
	var before:=next.duplicate(true)
	check(BattleLoopCombat._resolve_exchange(next,"leonard","enemy039_1",no_rng).is_empty() and next==before,"stale ordinary hit rejects before RNG or vitals mutation")
	var mobile:=fixture();var target:=BattlePlayLoop.unit(mobile,"enemy026_1")
	BattlePlayLoop._unit(mobile,"enemy026_1")["ai_target_id"]="thief";BattlePlayLoop._unit(mobile,"enemy026_1")["ai_call_target_id"]="thief"
	var fresh:=request(mobile,["thief"])
	check(BattlePlayLoop.unit(fresh,"enemy026_1")["ai_target_id"]=="" and BattlePlayLoop.unit(fresh,"enemy026_1")["ai_call_target_id"]=="","all calls/locks to departed target clear")
	var ai:=BattleLoopAI._prepare_ai_turn(fresh,"enemy026_1")
	check(ai["ok"] and ai["rows"][0]==null and ai["rows"][1]!=null,"new AI candidates exclude old target and retain available alternatives")
	var gone_friend:=request(mobile,["tina"])
	check(not BattlePlayLoop.recovery_target_ids(gone_friend).has("tina"),"moved/support item targets cannot include departed friend")
	var item:=BattleLoopInventory._resolve_item_use(gone_friend,"tina","thief","253",0)
	check(item.is_empty(),"departed inventory owner cannot use permanent item")
	var death:=fixture();BattlePlayLoop._set_unit_defeated(death,"enemy026_1",true)
	check(not BattlePresenceRules.prepare(death,["enemy026_1"],"winfail","dead")["changed"],"death then departure does not reclassify death or issue a new cleanup")
	check(not BattlePresenceRules.prepare(fixture(),["thief","thief"],"winfail","bad")["ok"],"duplicate batch rejected atomically")
	check(not BattlePresenceRules.prepare(fixture(),[4],"winfail","bad")["ok"],"non-string identity rejected atomically")

func transactions_and_endings()->void:
	var base:=fixture(true)
	var strike:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(base,"attack"),"enemy026_1",zero)
	check(not strike["last_attack"].is_empty(),"ordinary source mana/EXP transaction completed")
	var departed:=request(strike,["enemy026_1"])
	check(departed["last_attack"]==strike["last_attack"] and departed["action_end_sequence"]==strike["action_end_sequence"],"after-attack departure does not reopen completed MP/EXP or status tail")
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var terminal:=departed.duplicate(true);terminal["battle_outcome"]=outcome;terminal["interaction"]="battle_result";terminal["selected_unit_id"]="";BattlePlayLoop._clear_extra_action(terminal)
		check(BattlePlayLoop.step_ai_turn(terminal)==terminal and BattlePlayLoop.begin_wait_resolution(terminal)==terminal and BattlePlayLoop.finish_exhausted_action(terminal)==terminal,"terminal transaction cannot tick departure or next actor")
		check(BattleLoopCombat._resolve_exchange(terminal,"thief","tina",no_rng).is_empty(),"terminal ordinary entry cannot pay/attack")
		check(BattleCheckpoint.encode(terminal,VIEW)["ok"],"three terminal histories accept a quiet checkpoint")
	var chapter:=BattleFixture.loop()
	var historical:=BattlePlayLoop.unit(chapter,"enemy021_1")
	var first:=chapter.duplicate(true)
	BattleLoopScript._commit_departures(first,["enemy021_1"],"winfail", "event_3")
	check(BattlePlayLoop.unit(first,"enemy021_1")["hp"]==historical["hp"] and living_enemies(first)==living_enemies(chapter)-1,"scripted departure shares presence and the living enemy count")

func checkpoint()->void:
	var loop:=request(fixture(),["tina"])
	var view:=VIEW.duplicate(true);view["script_cutscene_consumed"]=loop["winfail_runtime"]["fired"].size()
	var saved:=BattleCheckpoint.encode(loop,view)
	check(saved["ok"],"departure has a valid saved history")
	if saved["ok"]:
		var restored:=BattleCheckpoint.decode(saved["bytes"], loop)
		check(restored["ok"] and restored["snapshot"]["loop"]==loop and restored["snapshot"]["view"]==view,"restore preserves exact history and script cursor without replay")
	for bad in ["flag","queue","lock","ledger","source","sequence","cursor"]:
		var corrupt:=loop.duplicate(true);var meta:=view.duplicate(true)
		match bad:
			"flag":BattlePlayLoop._unit(corrupt,"tina")["departed"]=false
			"queue":corrupt["turn_queue"]["slots"].append({"id":"tina","enabled":true,"action_ready":true,"live_speed":100})
			"lock":BattlePlayLoop._unit(corrupt,"thief")["ai_target_id"]="tina"
			"ledger":corrupt["winfail_runtime"]["departed_unit_ids"].clear()
			"source":BattlePlayLoop._unit(corrupt,"tina")["departure"]["source"]="unknown"
			"sequence":corrupt["last_departure"]["unit_ids"]=["thief"]
			"cursor":meta["script_cutscene_consumed"]=1000
		check(not BattleCheckpoint.encode(corrupt,meta)["ok"],"checkpoint rejects malformed departure "+bad)
	var carry:=BattlePlayLoop.CampaignCarryRules.capture(loop)
	var fresh:=BattlePlayLoop.apply_campaign_carry(run_mobile_jobs_tests.fresh(),carry)
	check(fresh["campaign_carry_receipt"]["errors"].is_empty() and not BattlePlayLoop.unit(fresh,"tina").get("departed",false),"battle departure does not delete a campaign party member")


func script_configuration()->void:
	var fixture_script = preload("res://tests/ScriptDepartureFixture.gd")
	var sample: Dictionary = fixture_script.build("delete")
	var loop: Dictionary = sample["loop"]
	var origin := BattleCheckpoint.configuration(loop)
	var before := BattleCheckpoint.encode(loop,VIEW)
	check(before["ok"],"before-event save requires no completed script cursor")
	var struck := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),sample["target_id"],zero)
	check(struck["departure_sequence"] == 0,"the strike itself scans nothing: the attacked event waits for the completion scan")
	# The owner acts twice (Mobile.fixture twice=true): the first half's repeat re-enters
	# phase 0, clearing the attacker global, so the second half's attack is the one read.
	var repeat := BattlePlayLoop.finish_exhausted_action(struck)
	check(repeat["extra_action"]["pending"] and repeat["departure_sequence"] == 0,"the first half of the extra action completes without a scan")
	var waited := BattlePlayLoop.choose_command(repeat,"wait")
	check(waited["scenario_ok"] and waited["departure_sequence"] == 0 and waited["winfail_runtime"]["fired"].is_empty() and not waited["extra_action"]["pending"],"a second half that does not attack completes without the first half's attack (the repeat re-entered phase 0)")
	var after := BattlePlayLoop.finish_exhausted_action(BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(repeat,"attack"),sample["target_id"],zero))
	check(after["departure_sequence"] == 1,"real attack fires a configured departure")
	check(BattleCheckpoint.encode(after,VIEW).get("reason") == "pending_saved_script_cutscene","unplayed script cannot be silently omitted from a quiet save")
	var view := VIEW.duplicate(true);view["script_cutscene_consumed"] = after["winfail_runtime"]["fired"].size()
	check(BattleCheckpoint.encode(after,view)["ok"],"completed script cursor permits quiet departure save")
	var changed := loop.duplicate(true)
	changed["winfail_script_rules"]["source_level"] += 1
	check(BattleCheckpoint.configuration(changed) != origin,"changed rule source invalidates the old cursor configuration")
	changed = loop.duplicate(true)
	own(changed, "script_presentation_source")["digest"] = "0".repeat(64)
	check(BattleCheckpoint.decode(before["bytes"], changed).get("reason") == "incompatible_save_configuration","changed timeline cannot reuse an old battle cursor")
	changed = loop.duplicate(true);changed.erase("departure_policy")
	check(BattleCheckpoint.configuration(changed) == "","old pre-presence saves require a fresh battle, not guessed migration")


func rearmed_binding()->void:
	var presentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
	var event := {"id":"delete","source_token":"actDeleteObject","args":["Enemy026",1]}
	var loop := {"winfail_runtime":{"fired":[{"key":"event_901"},{"key":"event_901"}],"departure_requests":[
		{"key":"event_901","name":"actDeleteObject","args":["Enemy026",1],"unit_ids":["first"],"firing_index":0},
		{"key":"event_901","name":"actDeleteObject","args":["Enemy026",1],"unit_ids":["second"],"firing_index":1}]}}
	var base := {"unit_id":"first"}
	check(presentation.departure_binding(loop,"event_901",0,event,[event],base)["unit_id"]=="first","first firing binds its committed departure")
	check(presentation.departure_binding(loop,"event_901",1,event,[event],base)["unit_id"]=="second","re-armed event cannot resurrect or delete the previous template instance")
	check(presentation.departure_binding(loop,"injected",1,event,[event],base)==base,"unrecorded presentation-only timelines preserve the shared coordinator contract")
	loop["winfail_runtime"]["departure_requests"].pop_back()
	check(presentation.departure_binding(loop,"event_901",1,event,[event],base)["unit_id"]=="","failed source lookup does not fall back to an opening actor")
	var sample: Dictionary = preload("res://tests/ScriptDepartureFixture.gd").build("rearm")
	var half := BattlePlayLoop.finish_exhausted_action(BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(sample["loop"],"attack"),"enemy026_1",zero))
	check(half["extra_action"]["pending"] and half["departure_sequence"] == 0,"the first half of the extra action completes without a scan")
	var first := BattlePlayLoop.finish_exhausted_action(BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(half,"attack"),"enemy026_1",zero))
	check(BattlePlayLoop.unit(first,"enemy026_1").get("departed",false) and not BattlePlayLoop.unit(first,"enemy026_2").get("departed",false),"first source lookup retires only the first currently registered instance")
	var view := VIEW.duplicate(true);view["script_cutscene_consumed"] = first["winfail_runtime"]["fired"].size()
	var encoded := BattleCheckpoint.encode(first,view)
	check(encoded["ok"],"first completed firing is saveable between two independent actions")
	if not encoded["ok"]: return
	var restored: Dictionary = BattleCheckpoint.decode(encoded["bytes"], first)["snapshot"]["loop"]
	# The owner's next attack action on the second instance: its completion scan re-reads the re-armed event.
	restored["last_attack"] = {"attacker_id": sample["owner_id"], "defender_id": "enemy026_2"}
	var second := BattlePlayLoop._resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(restored, true))
	check(second["departure_sequence"]==2 and BattlePlayLoop.unit(second,"enemy026_2").get("departed",false),"second firing skips the retired opening binding after restoration")
	check(second["winfail_runtime"]["departure_requests"].size()==2 and second["winfail_runtime"]["departure_requests"][1]["unit_ids"]==["enemy026_2"] and second["winfail_runtime"]["fired"].size()==2,"stable per-firing identity prevents double deletion or an empty replay")

func ai_script_handoff()->void:
	var sample: Dictionary = preload("res://tests/ScriptDepartureFixture.gd").build("ai")
	var loop: Dictionary = BattlePlayLoop.choose_command(sample["loop"],"wait")
	check(loop["interaction"]=="ai_resolving","authored friendly-AI strategy follows the real player wait")
	var half := BattlePlayLoop.step_ai_turn(loop,zero)
	check(half["scenario_ok"] and half["extra_action"]["pending"] and not BattlePlayLoop.unit(half,"wing").get("departed",false) and half["winfail_runtime"]["fired"].is_empty(),"the first half of an extra action completes without a scan (its repeat re-enters phase 0 and clears the attacker global)")
	var first := BattlePlayLoop.step_ai_turn(half,zero)
	check(first["scenario_ok"] and BattlePlayLoop.unit(first,"wing").get("departed",false),"new AI spell receipt fires the same completion-scan departure as a player cast")
	check(first["last_attack"]["sequence"]==first["last_combat"]["sequence"] and first["winfail_runtime"]["fired"].size()==1,"one accepted AI exchange delivers exactly one script check")
	check(not first["extra_action"]["pending"] and first["action_end_sequence"]==half["action_end_sequence"]+1,"the status/resource tail runs before the completion scan retires the current actor")
	var settled := first
	for _i in range(5):
		if settled["interaction"]!="ai_resolving":break
		settled = BattlePlayLoop.step_ai_turn(settled,zero)
	check(settled["winfail_runtime"]["fired"].size()==1,"later AI waiting cannot redispatch an older attack receipt")
