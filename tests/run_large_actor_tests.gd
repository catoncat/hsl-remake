extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const Body = preload("res://game/sim/FootprintRules.gd")
const Grid = preload("res://game/sim/TacticalGridRules.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Cases = preload("res://tests/run_position_equipment_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BIND := "magic:magicEARTH:magicCode05"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

static func source_large() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/actors/039.json"))["actor"]
	var source := Loop.BattleScenario.load_file("res://content/battles/first_battle.json")
	var actor := raw.duplicate(true)
	actor["coord"] = Vector2i(13,14);actor["grid_coord"] = actor["coord"]
	return Loop.unit(Loop.create(Loop.BattleScenario.units({"playable_units":[actor]}),"",source),"enemy039_1")

static func fixture(control_large: bool = true) -> Dictionary:
	var base := BattleFixture.loop()
	var giant := source_large()
	var player := Loop.unit(base,"leonard")
	var friend := Loop.unit(base,"enemy023_1")
	var foe := Loop.unit(base,"enemy021_1")
	if control_large:
		giant.merge({"id":"leonard","player_commandable":true,"battle_actor_role":Loop.ROLE_PLAYER,"coord":Vector2i(6,6)},true)
		giant["growth_profile"]["allocation"]="manual"
		player=giant
		foe["coord"]=Vector2i(10,6)
	else:
		player["coord"]=Vector2i(6,6)
		giant["coord"]=Vector2i(8,6);foe=giant
	friend.merge({"coord":Vector2i(16,16),"player_commandable":true,"battle_actor_role":Loop.ROLE_PLAYER,"live_speed":100},true)
	player["live_speed"]=200;player["hp"]=player["max_hp"];player["inventory"]=[233,236,227,31,248,241,232,0]
	player["hit_bonus_accum"]=1000;foe["live_speed"]=50;foe["hp"]=500;foe["max_hp"]=500;foe["no_attack"]=true;foe["inventory"]=[0,0,0,0,0,0,0,0]
	base["units"]=[player,friend,foe];base["tiles"]={};base["map_size"]=Vector2i(20,20);base["reinforcement_templates"]=[]
	for a in base["units"]:a["grid_coord"]=a["coord"];a["ai_home_coord"]=a["coord"]
	base["turn_queue"]=Loop.CoreTurnQueue.rebuild(base["units"])
	return Loop._return_to_player(base,"leonard")

func run() -> void:
	create_timer(180).timeout.connect(func():push_error("LARGE_ACTOR_TEST_TIMEOUT");quit(2))
	native_cases()
	spatial_transactions()
	skill_and_items()
	ai_cases()
	stale_plans_and_phases()
	terminal_cases()
	await trial_scene()
	print("LARGE_ACTOR_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=",checks)
	quit(0 if failures.is_empty() else 1)

func native_cases() -> void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_large_actor.json"))
	for row in packet["lookup"]:
		var c:Dictionary=row["input"];var units:Array=[]
		for i in range(c["actors"].size()):
			var a:Dictionary=c["actors"][i]
			if not a["registered"]:continue
			# Native lookup is a registered-pointer query, not the game's death filter.
			units.append({"id":str(i),"coord":Vector2i(int(a["coord"][0]),int(a["coord"][1])),"hp":100,"defeated":false,"traversal":{"size_type":int(a["large"]),"flying":false,"no_block":a["no_block"]}})
		var result:=Body.unit_at(units,Vector2i(int(c["query"][0]),int(c["query"][1])))
		check(int(result.get("id",-1))==int(row["native"]),"native body hit-test and blocker preference")
	for row in packet["flood"]:
		var c:Dictionary=row["input"];var dimensions:=Vector2i(int(c["size"][0]),int(c["size"][1]));var origin:=Vector2i(int(c["origin"][0]),int(c["origin"][1]))
		var mode:int=c["mode"];var actor:Dictionary={"id":"owner","coord":origin,"hp":100,"defeated":false,"battle_actor_role":"npc" if mode==7 else Loop.ROLE_ENEMY if mode==3 else Loop.ROLE_PLAYER,"traversal":{"size_type":int(c["large"]),"flying":mode==6,"no_block":false}}
		var tiles:Dictionary={};var units:Array=[actor]
		for y in range(dimensions.y):
			for x in range(dimensions.x):tiles[Vector2i(x,y)]={"elevation":int(c["base_height"]),"movement_flags":0}
		for cell in c["cells"]:
			var flags:int=cell[2]
			tiles[Vector2i(int(cell[0]),int(cell[1]))]={"elevation":flags>>24,"movement_flags":flags&0x974000}
		for index in range(c["occupants"].size()):
			var a:Dictionary=c["occupants"][index]
			units.append({"id":"other"+str(index),"coord":Vector2i(int(a["coord"][0]),int(a["coord"][1])),"hp":100,"defeated":false,"battle_actor_role":"npc" if a["side"]==0x40000 else Loop.ROLE_ENEMY if a["side"]==0x20000 else Loop.ROLE_FRIENDLY,"traversal":{"size_type":int(a["large"]),"flying":false,"no_block":a["no_block"]}})
		var before:=units.duplicate(true);var oldtiles:=tiles.duplicate(true)
		var envelope:=Grid.movement_reachability_envelope(actor,units,tiles,dimensions,int(c["budget"]))
		check(envelope["ok"] and units==before and tiles==oldtiles,"full body search is a read-only proposal")
		var expected:Array=row["native"];var half:int=c["budget"]
		for y in range(expected.size()):
			for x in range(expected[y].size()):
				var p:=origin+Vector2i(x-half,y-half)
				if p==origin:continue
				var value:int=expected[y][x];var wanted:bool=(value&0x7f)>0
				var route:Dictionary=envelope["reachable_by_coord"].get(p,envelope["transit_by_coord"].get(p,{}))
				var reached:bool=not route.is_empty()
				check(reached==wanted,"original entire-body flood reaches same anchor %s mode%d"%[p,mode])
				if wanted and reached:
					check(route["cost"]==half+1-(value&0x7f),"large source budget and obstacle/height cost agree")
					if value&0x80:check(not envelope["reachable_by_coord"].has(p),"original flying occupied footprint is transit-only")
	var large:=source_large()
	check(large["traversal"]["size_type"]==1 and Body.cells(large).size()==9,"source039 initializes exactly one nine-cell actor")
	for row in packet["stats"]:
		var c:Dictionary=row["input"];var actor:=large.duplicate(true);actor["level"]=int(c["level"]);actor["hp"]=int(c["hp"]);actor["mp"]=int(c["mp"])
		actor["combat_profile"].merge(c["attributes"],true);actor["equipment"]=[]
		for index in range(6):
			if c["equipment"][index]:actor["equipment"].append({"slot":Loop.EquipmentRules.SLOTS[index],"item_code":int(c["equipment"][index])})
		for native in row["native"]:
			actor=Loop.ProgressionRules.refresh_growth_stats(actor,BattleFixture.loop()["equipment_items"])
			check(actor["max_hp"]==native["values"]["max_hp"] and actor["move_point"]==native["values"]["move_point"] and actor["combat_profile"]["live_attack_damage"]==native["values"]["attack"],"source039 initialization/level/equipment refresh agrees with actual original return")

func spatial_transactions() -> void:
	var loop:=fixture();var actor:=Loop._unit(loop,"leonard");var origin:Vector2i=actor["coord"]
	check(Loop.weapon_pattern(loop,actor)["index"]==18,"source large weapon adds seventeen to normal range")
	var gear:=Cases.equip(loop,"accessory1",233)
	check(Loop.weapon_pattern(gear,Loop.unit(gear,"leonard"))["index"]==19,"large range extension uses the next original full mask")
	check(Loop.attack_cells(gear).size()>Loop.attack_cells(loop).size(),"gear changes actual player/AI attack footprint")
	for p in Body.cells(actor):check(Loop.unit_id_at_coord(loop,p)=="leonard","all body cells refer to the same identity")
	var moved:=Loop.move_unit_to(Loop.choose_command(loop,"move"),origin+Vector2i.LEFT)
	check(Loop.unit(moved,"leonard")["coord"]==origin+Vector2i.LEFT and moved["pending_move"],"one move updates the sole large anchor")
	check(Loop.unit_id_at_coord(moved,origin+Vector2i.RIGHT)=="" and Loop.unit_id_at_coord(moved,origin+Vector2i(-2,0))=="leonard","move releases trailing cells and claims leading cells together")
	var saved:=Save.encode(moved,Cases.VIEW);check(saved["ok"],"pending large movement can save")
	if saved["ok"]:
		var restored:=Save.decode(saved["bytes"], moved);check(restored["ok"] and restored["snapshot"]["loop"]==moved,"restored body/phase has no duplicated actor or re-applied gear")
	var cancelled:=Loop.cancel_pending_move(moved)
	check(Loop.unit(cancelled,"leonard")["coord"]==origin and not cancelled["moved_this_action"],"cancel restores every occupied cell from the original anchor")
	var block:=moved.duplicate(true);Loop._unit(block,"enemy023_1")["coord"]=origin+Vector2i.RIGHT
	check(Loop.cancel_pending_move(block)==block,"new occupant in the original ring rejects stale cancel atomically")
	var invalid:=loop.duplicate(true);Loop._unit(invalid,"enemy023_1")["coord"]=origin+Vector2i.RIGHT
	check(not Save.encode(invalid,Cases.VIEW)["ok"],"save refuses overlap inside a large body")
	var small:=fixture(false);var target:=Loop._unit(small,"enemy039_1");target["no_attack"]=false;target["combat_profile"]["attack_back"]=100
	var before_hp:int=target["hp"]
	var hit:=Loop.attack_coord(Loop.choose_command(small,"attack"),Vector2i(7,6),zero)
	check(hit["last_attack"].get("defender_id")==target["id"] and hit["last_attack"].get("cast_center")==Vector2i(7,6),"small actor attacks the clicked body edge while target center lies outside its range")
	check(Loop.unit(hit,target["id"])["hp"]<before_hp and not hit["last_attack"]["counter"].is_empty(),"one edge hit and native large counter settle exactly one exchange")
	var lethal:=fixture(false);Loop._unit(lethal,"enemy039_1")["hp"]=1
	var killed:=Loop.attack_coord(Loop.choose_command(lethal,"attack"),Vector2i(7,6),zero)
	check(Loop.unit(killed,"enemy039_1")["defeated"],"body-edge killing blow reaches shared death settlement")
	for p in Body.cells(Loop.unit(killed,"enemy039_1")):check(Loop.unit_id_at_coord(killed,p)=="","death releases all nine cells together")
	check(killed["rewarded_unit_ids"].count("enemy039_1")==1,"one large death never multiplies reward/EXP by body cells")

func skill_and_items() -> void:
	var loop:=fixture(false);var caster:=Loop._unit(loop,"leonard")
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"]=[BIND,Cases.WIND,Cases.HEAL,Cases.CURE]
	caster["growth_profile"]["source"]["has_magic"]=true;caster["growth_profile"]["source"]["magic_point"]=100
	caster.merge(Loop.ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true);caster["mp"]=caster["max_mp"]
	TestSuite.own(loop, "skill_book")["skills"][BIND]["fields"]["status_hit_ratio"]="100"
	var target:=Loop._unit(loop,"enemy039_1");var mp_before:int=caster["mp"]
	var spell:=Loop.attack_coord(Cases.selected(loop,BIND),Vector2i(8,5),zero)
	check(spell["last_attack"]["affected_targets"].size()==1 and Loop.StatusEffectRules.paralyzed(Loop.unit(spell,target["id"])),"overlapping multiple body cells only applies the range status once")
	check(Loop.unit(spell,"leonard")["mp"]==mp_before-16 and spell["last_attack"]["native_contribution"]==20,"one payment, one duration contribution and one EXP conversion")
	var empty:=Loop.attack_coord(Cases.selected(loop,BIND),Vector2i(6,5),zero)
	check(empty["last_attack"].get("affected_targets",[]).size()==1 and empty["last_attack"].get("cast_center")==Vector2i(6,5),"actual empty center may affect the outer footprint without recentering the spell")
	var allyloop:=fixture(false);var giant:=Loop._unit(allyloop,"enemy039_1")
	giant["battle_actor_role"]=Loop.ROLE_FRIENDLY;giant["no_attack"]=false;giant.merge(Loop.StatusEffectRules.apply(giant,"paralysis",2)["changes"],true)
	var use:=Loop.use_item(allyloop,"248",giant["id"],Loop.unit(allyloop,"leonard")["inventory"].find(248))
	check(use.get("last_item_use",{}).get("cured_paralysis",false) and not Loop.StatusEffectRules.paralyzed(Loop.unit(use,giant["id"])),"adjacent body-edge item assistance reaches the one large target")
	var guarded:=fixture();Loop._unit(guarded,"leonard").merge(Loop.StatusEffectRules.apply(Loop.unit(guarded,"leonard"),"paralysis",2)["changes"],true)
	guarded=Loop._return_to_player(guarded,"leonard");var before:=guarded.duplicate(true);var skip:=Loop.step_ai_turn(guarded,no_rng)
	check(skip["last_ai_action"]["kind"]=="paralysis_skip" and Loop.unit(skip,"leonard")["coord"]==Loop.unit(before,"leonard")["coord"],"large paralysis skip preserves anchor/occupancy and advances only one action")

func ai_cases() -> void:
	var loop:=fixture();var actor:=Loop._unit(loop,"leonard");actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY;actor["growth_profile"]["allocation"]="fixed_template"
	loop["interaction"]="ai_resolving";loop["selected_unit_id"]=""
	var target:=Loop._unit(loop,"enemy021_1");target["coord"]=Vector2i(12,6)
	for y in range(2,10):TestSuite.own(loop, "tiles")[Vector2i(9,y)]={"elevation":255,"blocks_movement":true}
	var prepared:=LoopAI._prepare_ai_turn(loop,"leonard")
	check(prepared["ok"],"large AI full-map approach prepares around a real obstruction")
	if not prepared["ok"]:return
	var first:=Loop.step_ai_turn(loop,zero)
	check(first["scenario_ok"] and first["last_ai_action"]["kind"]=="move","large AI follows a full-body detour when immediate attack is impossible")
	for p in first["last_ai_action"]["path"]:
		var projected:=actor.duplicate(true);projected["coord"]=p
		check(Loop.TraversalRules.placement_error(projected,first["units"],first["tiles"],first["map_size"])=="","every large path anchor has legal occupied cells")
	var clear:=fixture(false);var small:=Loop._unit(clear,"leonard");small["player_commandable"]=false;small["battle_actor_role"]=Loop.ROLE_FRIENDLY
	clear["selected_unit_id"]="";clear["interaction"]="ai_resolving"
	var chosen:=LoopAI._prepare_ai_turn(clear,"leonard")
	check(chosen["ok"] and chosen["physical"].has("enemy039_1") and chosen["physical"]["enemy039_1"]["cost"]==0,"small AI sees an in-range body edge without unnecessary movement toward the center")

static func spell_kit(loop: Dictionary) -> void:
	var actor:=Loop._unit(loop,"leonard")
	TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["supported_initial_ids"]=[BIND,Cases.WIND,Cases.HEAL,Cases.CURE]
	actor["growth_profile"]["source"]["has_magic"]=true
	actor["growth_profile"]["source"]["magic_point"]=100
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["mp"]=actor["max_mp"]

func stale_plans_and_phases() -> void:
	var template:=fixture();spell_kit(template)
	# Source039/job94 cannot equip the caster-only ring. Explicitly author the
	# already-proven innate permission for this synthetic large-caster fixture.
	TestSuite.own(template, "skill_book")["actors"]["039"]["move_magic_use"]=true
	var choice:Dictionary={"skill_id":Cases.WIND,"target_id":"enemy021_1","destination":Vector2i(8,6),"cast_center":Vector2i(10,6)}
	var control:=template.duplicate(true)
	check(not LoopAI._execute_ai_skill_choice(control,"leonard",choice,zero).is_empty(),"large moving-cast baseline uses a complete legal body route")
	for reason in ["blocked_ring","dead_target","no_mp","silence","lost_permission","less_budget"]:
		var changed:=template.duplicate(true);var actor:=Loop._unit(changed,"leonard")
		match reason:
			"blocked_ring":Loop._set_unit_coord(changed,"enemy023_1",Vector2i(8,6))
			"dead_target":Loop._set_unit_defeated(changed,"enemy021_1",true)
			"no_mp":actor["mp"]=0
			"silence":actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
			"lost_permission":TestSuite.own(changed, "skill_book")["actors"]["039"]["move_magic_use"]=false
			"less_budget":actor["base_move_point"]=1;actor["move_point"]=1
		var before:=changed.duplicate(true)
		check(LoopAI._execute_ai_skill_choice(changed,"leonard",choice,no_rng).is_empty() and changed==before,"stale whole-body intent rejected before movement/payment/EXP: "+reason)
	var changed:=fixture();var actor:=Loop._unit(changed,"leonard")
	actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
	var oldplan:=LoopAI._prepare_ai_turn(changed,"leonard")
	Loop._set_unit_coord(changed,"enemy023_1",Vector2i(8,6))
	var freshplan:=LoopAI._prepare_ai_turn(changed,"leonard")
	check(oldplan["ok"] and freshplan["ok"] and oldplan["approaches"]["enemy021_1"]["path"]!=freshplan["approaches"]["enemy021_1"]["path"],"AI replans its entire footprint when a previous approach ring becomes occupied")
	var second:=Loop.unit(changed,"enemy021_1").duplicate(true);second["id"]="another_foe";second["coord"]=Vector2i(11,9);second["grid_coord"]=second["coord"]
	changed["units"].append(second);Loop._set_unit_defeated(changed,"enemy021_1",true)
	freshplan=LoopAI._prepare_ai_turn(changed,"leonard")
	check(freshplan["ok"] and not freshplan["approaches"].has("enemy021_1") and freshplan["approaches"].has("another_foe"),"dead target's body is released and another reachable candidate replaces it")
	var loop:=fixture();var first:=source_large();var later:=source_large()
	first.merge({"coord":Vector2i(9,6),"grid_coord":Vector2i(9,6),"hp":1,"no_attack":true,"live_speed":50},true)
	later.merge({"id":"later039","coord":Vector2i(9,9),"grid_coord":Vector2i(9,9),"hp":500,"max_hp":500,"no_attack":true,"live_speed":40},true)
	loop["units"]=[Loop.unit(loop,"leonard"),Loop.unit(loop,"enemy023_1"),first,later]
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	TestSuite.own(loop, "skill_book")["actors"]["039"]["double_attack"]=true
	loop=Cases.equip(loop,"accessory2",227);actor=Loop._unit(loop,"leonard");actor["exp"]=99
	actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	loop=Loop.attack_coord(Loop.choose_command(loop,"attack"),Vector2i(8,6),zero)
	check(loop["last_attack"]["followups"].is_empty() and Loop.unit(loop,"leonard")["level"]>1 and loop["rewarded_unit_ids"].count("enemy039_1")==1,"large lethal first hit truncates double attack and awards one native kill/growth")
	loop=Loop.finish_exhausted_action(loop)
	check(loop["extra_action"]["pending"] and not loop["moved_this_action"] and not loop["attacked_this_action"] and int(Loop.unit(loop,"leonard")["status_counters"]["poison"])&0xffff==3,"independent second action starts without ticking the large owner's poison")
	var saved:=Save.encode(loop,Cases.VIEW);check(saved["ok"],"large second action and pending growth checkpoint together")
	if saved["ok"]:loop=Save.decode(saved["bytes"], loop)["snapshot"]["loop"]
	loop=Loop.move_unit_to(Loop.choose_command(loop,"move"),Vector2i(7,6))
	loop=Loop.attack_coord(Loop.choose_command(loop,"attack"),Vector2i(8,8),zero)
	check(loop["last_attack"]["followups"].size()==1 and loop["last_attack"]["defender_id"]=="later039","second action attacks the new body edge with its own two-hit series")
	loop=Loop.finish_exhausted_action(loop)
	check(not loop["extra_action"]["pending"] and int(Loop.unit(loop,"leonard")["status_counters"]["poison"])&0xffff==2 and loop["selected_unit_id"]=="enemy023_1","only the final action ticks poison once and hands the queue on")
	var malformed:=fixture();Loop._unit(malformed,"leonard")["traversal"]="not a footprint"
	check(Save.encode(malformed,Cases.VIEW).get("reason")=="invalid_saved_actor_traversal","malformed saved body is rejected before geometry allocation or access")
	var fallback:=fixture();spell_kit(fallback);actor=Loop._unit(fallback,"leonard")
	actor.merge({"player_commandable":false,"battle_actor_role":Loop.ROLE_FRIENDLY,"mp":0,"no_attack":true,"inventory":[0,0,0,0,0,0,0,0]},true)
	actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	fallback["interaction"]="ai_resolving";fallback["selected_unit_id"]=""
	var idle:=Loop.step_ai_turn(fallback,zero)
	check(idle["scenario_ok"] and idle["last_ai_action"]["kind"]=="wait" and idle["action_end_sequence"]==1 and Loop.unit(idle,"leonard")["coord"]==actor["coord"],"large AI with zero resources/silence/no attack ends once without phantom movement")

func terminal_cases() -> void:
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var loop:=fixture()
		var actor:=Loop._unit(loop,"leonard");var enemy:=Loop._unit(loop,"enemy021_1")
		if outcome==BattleOutcome.VICTORY_ESCAPE:actor["coord"]=loop["escape_zone"][0];loop=Loop.choose_command(loop,"wait")
		else:
			enemy["coord"]=Vector2i(8,6)
			if outcome==BattleOutcome.VICTORY_ENEMIES_CLEARED:enemy["hp"]=1;actor["exp"]=99
			else:
				actor["hp"]=1;enemy["no_attack"]=false;enemy["hit_bonus_accum"]=1000;enemy["combat_profile"]["attack_back"]=100;enemy["combat_profile"]["live_attack_damage"]=1000
			loop=Loop.attack_target(Loop.choose_command(loop,"attack"),enemy["id"],zero)
		check(loop["battle_outcome"]==outcome and Save.encode(loop,Cases.VIEW)["ok"],"large actor complete terminal/checkpoint boundary: "+BattleOutcome.describe(outcome))
		check(Loop.finish_exhausted_action(loop)==loop and Loop.step_ai_turn(loop,no_rng)==loop,"terminal body and action state stay frozen")

func trial_scene() -> void:
	var scenario:=Loop.BattleScenario.load_file("res://content/battles/large_actor_trial.json")
	var loop:=Loop.create([],"",scenario)
	check(loop["scenario_ok"] and Loop.unit(loop,"large039_friend")["traversal"]["size_type"]==1,"published development scenario uses the same live PlayLoop and source body")
	loop=Loop.begin_battle(loop)
	while loop["interaction"]=="ai_resolving":loop=Loop.step_ai_turn(loop,zero)
	check(Save.encode(loop,Cases.VIEW)["ok"],"development placement and full body are checkpoint-consistent")
	var scene=load("res://game/battle/development/LargeActorTrial.tscn").instantiate();root.add_child(scene);await create_timer(0.5).timeout
	check(scene.play_loop["scenario_ok"] and scene.actor_node_for_unit("large039_friend")!=null,"real source039 scene instantiates its original actor resources")
	scene.status_panel.show_unit(Loop.unit(scene.play_loop,"large039_friend"))
	check(scene.status_panel.vitals.values["role"].text=="海輝魔" and scene.status_panel.vitals.values["race"].text=="獸族","source039 title and race are actual source display fields")
	check(scene.status_panel.equipment_view.icons["weapon"].texture==null and scene.status_panel.equipment_view.labels["weapon"].text=="觸手","native empty claw glyph retains the real weapon name without a fabricated image")
	for sound in scene.find_children("*","AudioStreamPlayer",true,false):sound.stop();sound.stream=null
	scene.queue_free();await process_frame;await create_timer(0.1).timeout

func zero(_bound:int)->int:return 0
func no_rng(_bound:int)->int:
	check(false,"rejected/skip/terminal path cannot consume combat RNG");return 0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error(message)
