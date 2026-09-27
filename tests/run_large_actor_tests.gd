extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const FootprintRules = preload("res://game/sim/FootprintRules.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_position_equipment_tests = preload("res://tests/run_position_equipment_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const BIND := "magic:magicEARTH:magicCode05"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

static func source_large() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/actors/039.json"))["actor"]
	var source := BattlePlayLoop.BattleScenario.load_file("res://content/battles/first_battle.json")
	var actor := raw.duplicate(true)
	actor["coord"] = Vector2i(13,14);actor["grid_coord"] = actor["coord"]
	return BattlePlayLoop.unit(BattlePlayLoop.create(BattlePlayLoop.BattleScenario.units({"playable_units":[actor]}),"",source),"enemy039_1")

static func fixture(control_large: bool = true) -> Dictionary:
	var base := BattleFixture.loop()
	var giant := source_large()
	var player := BattlePlayLoop.unit(base,"leonard")
	var friend := BattlePlayLoop.unit(base,"enemy023_1")
	var foe := BattlePlayLoop.unit(base,"enemy021_1")
	if control_large:
		giant.merge({"id":"leonard","player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"coord":Vector2i(6,6)},true)
		giant["growth_profile"]["allocation"]="manual"
		player=giant
		foe["coord"]=Vector2i(10,6)
	else:
		player["coord"]=Vector2i(6,6)
		giant["coord"]=Vector2i(8,6);foe=giant
	friend.merge({"coord":Vector2i(16,16),"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"live_speed":100},true)
	player["live_speed"]=200;player["hp"]=player["max_hp"];player["inventory"]=[233,236,227,31,248,241,232,0]
	player["hit_bonus_accum"]=1000;foe["live_speed"]=50;foe["hp"]=500;foe["max_hp"]=500;foe["no_attack"]=true;foe["inventory"]=[0,0,0,0,0,0,0,0]
	base["units"]=[player,friend,foe];base["tiles"]={};base["map_size"]=Vector2i(20,20);base["reinforcement_templates"]=[]
	for a in base["units"]:a["grid_coord"]=a["coord"];a["ai_home_coord"]=a["coord"]
	base["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(base["units"])
	return BattlePlayLoop._return_to_player(base,"leonard")

func run() -> void:
	create_timer(180).timeout.connect(func():push_error("LARGE_ACTOR_TEST_TIMEOUT");quit(2))
	native_cases()
	spatial_transactions()
	skill_and_items()
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
		var result:=FootprintRules.unit_at(units,Vector2i(int(c["query"][0]),int(c["query"][1])))
		check(int(result.get("id",-1))==int(row["native"]),"native body hit-test and blocker preference")
	for row in packet["flood"]:
		var c:Dictionary=row["input"];var dimensions:=Vector2i(int(c["size"][0]),int(c["size"][1]));var origin:=Vector2i(int(c["origin"][0]),int(c["origin"][1]))
		var mode:int=c["mode"];var actor:Dictionary={"id":"owner","coord":origin,"hp":100,"defeated":false,"battle_actor_role":"npc" if mode==7 else BattlePlayLoop.ROLE_ENEMY if mode==3 else BattlePlayLoop.ROLE_PLAYER,"traversal":{"size_type":int(c["large"]),"flying":mode==6,"no_block":false}}
		var tiles:Dictionary={};var units:Array=[actor]
		for y in range(dimensions.y):
			for x in range(dimensions.x):tiles[Vector2i(x,y)]={"elevation":int(c["base_height"]),"movement_flags":0}
		for cell in c["cells"]:
			var flags:int=cell[2]
			tiles[Vector2i(int(cell[0]),int(cell[1]))]={"elevation":flags>>24,"movement_flags":flags&0x974000}
		for index in range(c["occupants"].size()):
			var a:Dictionary=c["occupants"][index]
			units.append({"id":"other"+str(index),"coord":Vector2i(int(a["coord"][0]),int(a["coord"][1])),"hp":100,"defeated":false,"battle_actor_role":"npc" if a["side"]==0x40000 else BattlePlayLoop.ROLE_ENEMY if a["side"]==0x20000 else BattlePlayLoop.ROLE_FRIENDLY,"traversal":{"size_type":int(a["large"]),"flying":false,"no_block":a["no_block"]}})
		var before:=units.duplicate(true);var oldtiles:=tiles.duplicate(true)
		var envelope:=TacticalGridRules.movement_reachability_envelope(actor,units,tiles,dimensions,int(c["budget"]))
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
	check(large["traversal"]["size_type"]==1 and FootprintRules.cells(large).size()==9,"source039 initializes exactly one nine-cell actor")
	for row in packet["stats"]:
		var c:Dictionary=row["input"];var actor:=large.duplicate(true);actor["level"]=int(c["level"]);actor["hp"]=int(c["hp"]);actor["mp"]=int(c["mp"])
		actor["combat_profile"].merge(c["attributes"],true);actor["equipment"]=[]
		for index in range(6):
			if c["equipment"][index]:actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[index],"item_code":int(c["equipment"][index])})
		for native in row["native"]:
			actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,BattleFixture.loop()["equipment_items"])
			check(actor["max_hp"]==native["values"]["max_hp"] and actor["move_point"]==native["values"]["move_point"] and actor["combat_profile"]["live_attack_damage"]==native["values"]["attack"],"source039 initialization/level/equipment refresh agrees with actual original return")

func spatial_transactions() -> void:
	var loop:=fixture();var actor:=BattlePlayLoop._unit(loop,"leonard");var origin:Vector2i=actor["coord"]
	check(BattlePlayLoop.weapon_pattern(loop,actor)["index"]==18,"source large weapon adds seventeen to normal range")
	var gear:=run_position_equipment_tests.equip(loop,"accessory1",233)
	check(BattlePlayLoop.weapon_pattern(gear,BattlePlayLoop.unit(gear,"leonard"))["index"]==19,"large range extension uses the next original full mask")
	check(BattlePlayLoop.attack_cells(gear).size()>BattlePlayLoop.attack_cells(loop).size(),"gear changes actual player/AI attack footprint")
	for p in FootprintRules.cells(actor):check(BattlePlayLoop.unit_id_at_coord(loop,p)=="leonard","all body cells refer to the same identity")
	var moved:=BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop,"move"),origin+Vector2i.LEFT)
	check(BattlePlayLoop.unit(moved,"leonard")["coord"]==origin+Vector2i.LEFT and moved["pending_move"],"one move updates the sole large anchor")
	check(BattlePlayLoop.unit_id_at_coord(moved,origin+Vector2i.RIGHT)=="" and BattlePlayLoop.unit_id_at_coord(moved,origin+Vector2i(-2,0))=="leonard","move releases trailing cells and claims leading cells together")
	var saved:=BattleCheckpoint.encode(moved,run_position_equipment_tests.VIEW);check(saved["ok"],"pending large movement can save")
	if saved["ok"]:
		var restored:=BattleCheckpoint.decode(saved["bytes"], moved);check(restored["ok"] and restored["snapshot"]["loop"]==moved,"restored body/phase has no duplicated actor or re-applied gear")
	var cancelled:=BattlePlayLoop.cancel_pending_move(moved)
	check(BattlePlayLoop.unit(cancelled,"leonard")["coord"]==origin and not cancelled["moved_this_action"],"cancel restores every occupied cell from the original anchor")
	var block:=moved.duplicate(true);BattlePlayLoop._unit(block,"enemy023_1")["coord"]=origin+Vector2i.RIGHT
	check(BattlePlayLoop.cancel_pending_move(block)==block,"new occupant in the original ring rejects stale cancel atomically")
	var invalid:=loop.duplicate(true);BattlePlayLoop._unit(invalid,"enemy023_1")["coord"]=origin+Vector2i.RIGHT
	check(not BattleCheckpoint.encode(invalid,run_position_equipment_tests.VIEW)["ok"],"save refuses overlap inside a large body")
	var small:=fixture(false);var target:=BattlePlayLoop._unit(small,"enemy039_1");target["no_attack"]=false;target["combat_profile"]["attack_back"]=100
	var before_hp:int=target["hp"]
	var hit:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(small,"attack"),Vector2i(7,6),zero)
	check(hit["last_attack"].get("defender_id")==target["id"] and hit["last_attack"].get("cast_center")==Vector2i(7,6),"small actor attacks the clicked body edge while target center lies outside its range")
	check(BattlePlayLoop.unit(hit,target["id"])["hp"]<before_hp and not hit["last_attack"]["counter"].is_empty(),"one edge hit and native large counter settle exactly one exchange")
	var lethal:=fixture(false);BattlePlayLoop._unit(lethal,"enemy039_1")["hp"]=1
	var killed:=BattlePlayLoop.attack_coord(BattlePlayLoop.choose_command(lethal,"attack"),Vector2i(7,6),zero)
	check(BattlePlayLoop.unit(killed,"enemy039_1")["defeated"],"body-edge killing blow reaches shared death settlement")
	for p in FootprintRules.cells(BattlePlayLoop.unit(killed,"enemy039_1")):check(BattlePlayLoop.unit_id_at_coord(killed,p)=="","death releases all nine cells together")
	check(killed["rewarded_unit_ids"].count("enemy039_1")==1,"one large death never multiplies reward/EXP by body cells")

func skill_and_items() -> void:
	var loop:=fixture(false);var caster:=BattlePlayLoop._unit(loop,"leonard")
	TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"]=[BIND,run_position_equipment_tests.WIND,run_position_equipment_tests.HEAL,run_position_equipment_tests.CURE]
	caster["growth_profile"]["source"]["has_magic"]=true;caster["growth_profile"]["source"]["magic_point"]=100
	caster.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true);caster["mp"]=caster["max_mp"]
	TestSuite.own(loop, "skill_book")["skills"][BIND]["fields"]["status_hit_ratio"]="100"
	var target:=BattlePlayLoop._unit(loop,"enemy039_1");var mp_before:int=caster["mp"]
	var spell:=BattlePlayLoop.attack_coord(run_position_equipment_tests.selected(loop,BIND),Vector2i(8,5),zero)
	check(spell["last_attack"]["affected_targets"].size()==1 and BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(spell,target["id"])),"overlapping multiple body cells only applies the range status once")
	check(BattlePlayLoop.unit(spell,"leonard")["mp"]==mp_before-16 and spell["last_attack"]["native_contribution"]==20,"one payment, one duration contribution and one EXP conversion")
	var empty:=BattlePlayLoop.attack_coord(run_position_equipment_tests.selected(loop,BIND),Vector2i(6,5),zero)
	check(empty["last_attack"].get("affected_targets",[]).size()==1 and empty["last_attack"].get("cast_center")==Vector2i(6,5),"actual empty center may affect the outer footprint without recentering the spell")
	var allyloop:=fixture(false);var giant:=BattlePlayLoop._unit(allyloop,"enemy039_1")
	giant["battle_actor_role"]=BattlePlayLoop.ROLE_FRIENDLY;giant["no_attack"]=false;giant.merge(BattlePlayLoop.StatusEffectRules.apply(giant,"paralysis",2)["changes"],true)
	var use:=BattlePlayLoop.use_item(allyloop,"248",giant["id"],BattlePlayLoop.unit(allyloop,"leonard")["inventory"].find(248))
	check(use.get("last_item_use",{}).get("cured_paralysis",false) and not BattlePlayLoop.StatusEffectRules.paralyzed(BattlePlayLoop.unit(use,giant["id"])),"adjacent body-edge item assistance reaches the one large target")
	var guarded:=fixture();BattlePlayLoop._unit(guarded,"leonard").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(guarded,"leonard"),"paralysis",2)["changes"],true)
	guarded=BattlePlayLoop._return_to_player(guarded,"leonard");var before:=guarded.duplicate(true);var skip:=BattlePlayLoop.step_ai_turn(guarded,no_rng)
	check(skip["last_ai_action"]["kind"]=="paralysis_skip" and BattlePlayLoop.unit(skip,"leonard")["coord"]==BattlePlayLoop.unit(before,"leonard")["coord"],"large paralysis skip preserves anchor/occupancy and advances only one action")

static func spell_kit(loop: Dictionary) -> void:
	var actor:=BattlePlayLoop._unit(loop,"leonard")
	TestSuite.own(loop, "skill_book")["actors"][actor["actor_id"]]["supported_initial_ids"]=[BIND,run_position_equipment_tests.WIND,run_position_equipment_tests.HEAL,run_position_equipment_tests.CURE]
	actor["growth_profile"]["source"]["has_magic"]=true
	actor["growth_profile"]["source"]["magic_point"]=100
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["mp"]=actor["max_mp"]

func trial_scene() -> void:
	var scenario:=BattlePlayLoop.BattleScenario.load_file("res://content/battles/large_actor_trial.json")
	var loop:=BattlePlayLoop.create([],"",scenario)
	check(loop["scenario_ok"] and BattlePlayLoop.unit(loop,"large039_friend")["traversal"]["size_type"]==1,"published development scenario uses the same live PlayLoop and source body")
	loop=BattlePlayLoop.begin_battle(loop)
	while loop["interaction"]=="ai_resolving":loop=BattlePlayLoop.step_ai_turn(loop,zero)
	check(BattleCheckpoint.encode(loop,run_position_equipment_tests.VIEW)["ok"],"development placement and full body are checkpoint-consistent")
	var scene=load("res://game/battle/development/LargeActorTrial.tscn").instantiate();root.add_child(scene);await create_timer(0.5).timeout
	check(scene.play_loop["scenario_ok"] and scene.actor_node_for_unit("large039_friend")!=null,"real source039 scene instantiates its original actor resources")
	scene.status_panel.show_unit(BattlePlayLoop.unit(scene.play_loop,"large039_friend"))
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
