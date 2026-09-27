extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Growth = preload("res://tests/run_growth_lifecycle_tests.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WATER := "magic:magicWATER:magicCode01"
const CENTER := Vector2i(11,16)

func _init() -> void:
	tag = "WATER_STRIKE_TESTS"

static func fixture(learn: bool = true) -> Dictionary:
	var loop := Growth.fixture(3)
	Loop._unit(loop,"tina")["coord"]=Vector2i(10,16)
	Loop._unit(loop,"companion")["coord"]=Vector2i(10,15)
	var enemy := Loop._unit(loop,"enemy021_1")
	enemy["coord"]=Vector2i(12,16);enemy["ai_home_coord"]=enemy["coord"]
	var second:=enemy.duplicate(true)
	second["id"]="enemy021_2";second["coord"]=Vector2i(11,15);second["ai_home_coord"]=second["coord"]
	loop["units"].append(second)
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	loop=Loop._return_to_player(loop,"tina")
	if learn:loop=Loop.finish_exhausted_action(Growth.cast(loop,Growth.HEAL,"companion",zero))
	return loop

static func selected(loop:Dictionary) -> Dictionary:
	return Loop.choose_magic(Loop.choose_command(loop,"magic"),WATER)

static func cast(loop:Dictionary,rng:Variant=null) -> Dictionary:
	return Loop.attack_target(selected(loop),"enemy021_1",rng,CENTER)

func run() -> void:
	var loop:=fixture()
	check(loop["skill_book"]["skills"].has(WATER),"newly earned Water Strike must be a registered usable action")
	if not loop["skill_book"]["skills"].has(WATER):return
	native_cases()
	ownership_and_transactions()
	rejection_and_resources()
	large_and_equipment()
	await presentation_case()

func native_cases():
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_water_strike.json"))
	for row in packet["rolls"]:
		var draws:Array=row["draws"].duplicate(true)
		var actual:=Loop.StatusApplicationRules.Rolls.roll(row["input"],func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"water native full-return draw order")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(actual["value"]==int(row["native"]["value"]) and actual["hit_bonus_after"]==int(row["native"]["hit_bonus_after"]) and draws.is_empty(),"water helper equals original full return")
	for row in packet["applications"]:
		var c:Dictionary=row["input"]
		var target:Dictionary={"hp":int(c["hp"]),"status_flags":0,"status_counters":{"poison":0,"paralysis":0,"no_magic":0}}
		var draws:Array=row["draws"].duplicate(true)
		var actual:=Loop.StatusApplicationRules.resolve({"function_mask":1,"immunities":0,"roll_input":c},target,func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"water HP prefix consumes original draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(actual["target_changes"]["hp"]==int(row["native"]["hp"]) and actual["native_contribution"]==int(row["native"]["contribution"]) and draws.is_empty(),"water HP cap and contribution equal native prefix")

func ownership_and_transactions():
	var raw:=fixture(false);var loop:=fixture()
	check(Loop.SkillResolutionRules.ownership_error(Loop.unit(raw,"tina"),WATER,raw["skill_book"])=="skill_not_owned","priest cannot anticipate the unearned water skill")
	check(Loop.unit(loop,"tina")["level"]==4 and Growth.Learning.owns(Loop.unit(loop,"tina"),WATER),"actual paid healing learns water before the independent second action")
	check(loop["skill_book"]["actors"]["025"]["supported_initial_ids"].has(WATER) and not loop["skill_book"]["actors"]["026"]["supported_initial_ids"].has(WATER),"source025 water ownership never leaks into source026 wind/fire mage")
	var field:=Loop.skill_fields(loop,WATER)
	check(field["effect_range"]=="range1Cell" and field["expend"]=="8" and field["damage"]=="16,24","use real source cross and cost, not a synthetic wind range")
	var footprint:=Loop.SkillTargetRules.effect_cells(CENTER,field,loop["skill_target_data"],loop["map_size"])
	check(footprint.size()==5 and footprint.has(CENTER+Vector2i.RIGHT) and not footprint.has(CENTER+Vector2i(1,1)),"water crosses five cells without diagonal expansion")
	check(Loop.magic_target_id_at_coord(selected(loop),CENTER)!="","empty cross center resolves a real affected enemy")
	for health in [1,800]:
		var input:=loop.duplicate(true)
		Loop._unit(input,"enemy021_2")["hp"]=health
		var before:=input.duplicate(true)
		var after:=cast(input,zero)
		check(not after["last_attack"].is_empty() and after["last_attack"].get("skill_id")==WATER,"actual water action settles")
		if after["last_attack"].get("skill_id")!=WATER:continue
		var receipt:Dictionary=after["last_attack"]
		check(receipt["affected_targets"].size()==2 and receipt["cast_center"]==CENTER,"one cast hits two unique actors through an empty source center")
		check(input==before and Loop.unit(after,"tina")["mp"]==Loop.unit(input,"tina")["mp"]-8,"all target proposals commit one eight-MP debit and preserve input")
		var points:=0
		for hit in receipt["affected_targets"]:
			points+=int(hit["experience_basis"]["points"])
			check(hit["attacker_before"]["level"]==4 and hit["actual_damage"]>0,"all targets see the same pre-award caster")
		check(receipt["experience"]["gained"]==points,"one final award equals both native target conversions")
		check(Loop.unit(after,"enemy021_2")["hp"]==0 if health==1 else Loop.unit(after,"enemy021_2")["hp"]>0,"mixed lethal/nonlethal outcomes")
		for state in [input,after,Loop.finish_exhausted_action(after)]:
			var encoded:=Save.encode(state,Growth.VIEW)
			check(encoded["ok"],"water checkpoint supports exact action stage: "+str(encoded.get("reason")))
			if encoded["ok"]:check(Save.decode(encoded["bytes"], state)["snapshot"]["loop"]==state,"F9 does not pay, grow, learn or consume any stream again")
	var resistant:=loop.duplicate(true)
	Loop._unit(resistant,"enemy021_2")["combat_profile"]["resist_by_type"]["1"]=80
	Loop._unit(resistant,"enemy021_2")["combat_profile"]["resist_by_type"]["3"]=0
	var prepared:=Loop.StatusApplicationRules.prepare(Loop.unit(resistant,"tina"),Loop.unit(resistant,"enemy021_2"),field,resistant["skill_book"],resistant["skill_target_data"],resistant["equipment_items"])
	check(prepared["ok"] and prepared["roll_input"]["resistance"]==80,"water selects water resistance index1, not fire or absent element")
	var missed:=cast(loop,func(bound):return maxi(0,bound-1))
	check(missed["last_attack"].get("skill_id")==WATER and missed["last_attack"]["affected_targets"][0]["damage"]==0,"main water hit can miss while still paying once")
	var carry:Dictionary=JSON.parse_string(JSON.stringify(Loop.CampaignCarryRules.capture(loop)))
	# Carry enters an actually fresh idle battle, never an already active fixture.
	var fresh:=Growth.Priest.priest_initial()
	# Source stats belong to the destination scenario, not the carried record.
	# Give this authored next-battle fixture a genuinely first acting priest.
	Loop._unit(fresh,"tina")["growth_profile"]["source"]["speed"]=500
	for unit in fresh["units"]:
		unit["coord"]={"tina":Vector2i(10,16),"companion":Vector2i(10,15),"enemy021_1":Vector2i(12,16)}[unit["id"]]
	var resumed:=Loop.initialize_roster_growth(Loop.apply_campaign_carry(fresh,carry))
	resumed=Loop._return_to_player(resumed,"tina")
	check(resumed["campaign_carry_receipt"]["errors"].is_empty() and Growth.Learning.owns(Loop.unit(resumed,"tina"),WATER),"actual campaign JSON carries the earned water record without relearning")
	check(resumed["turn_queue"]["slots"][0]["id"]=="tina","carried caster acts at its actual destination initiative slot")
	var carried_cast:=cast(resumed,zero)
	check(carried_cast["last_attack"].get("skill_id")==WATER,"the carried learned record enables a real water transaction in the next battle")

func rejection_and_resources():
	for variant in ["mp","silence","paralysis","corrupt_second","unearned","terminal"]:
		var loop:=fixture(variant!="unearned")
		var actor:=Loop._unit(loop,"tina")
		match variant:
			"mp":actor["mp"]=7
			"silence":actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
			"paralysis":actor.merge(Loop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true)
			"corrupt_second":Loop._unit(loop,"enemy021_2")["combat_profile"]["resist_by_type"].erase("1")
			"terminal":loop["battle_outcome"]=BattleOutcome.DEFEAT_FALLEN
		var before:=loop.duplicate(true)
		var called:=[0]
		var after:=cast(loop,func(_bound):called[0]+=1;return 0)
		check(called[0]==0 and after["units"]==before["units"] and after.get("last_combat",{})==before.get("last_combat",{}),"reject whole water action before payment/RNG/target effect: "+variant)

func presentation_case():
	var loop:=fixture();var after:=cast(loop,zero)
	var clip=load("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(clip);clip.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json");clip.set_process(false)
	var events:=[0,0]
	clip.released.connect(func(_s,_a,_d,_c):events[0]+=1)
	clip.impact.connect(func(_s,_a,_d,_c):events[1]+=1)
	var saved:=after.duplicate(true)
	clip.sparks[0].show();clip.blade.show()
	clip.play(after["last_attack"],Loop.unit(after,"tina"),Loop.unit(after,"enemy021_1"),false,Vector2(320,240),Vector2(260,300),[Vector2(340,240),Vector2(310,210)])
	clip._process(0.01)
	# 緹娜's own m_action lead (R31: the P002_101 banner over the shadowed map) opens the shot;
	# the attacker sprite is that banner, not a duel close-up.
	var lead:Dictionary=clip.cast_lead(clip.clips[0],"magic")
	check(not clip.scenery.visible and clip.attacker_sprite.visible and clip.attacker_sprite.texture.resource_path.ends_with("002/magic-0.png") and not clip.blade.visible and clip.sparks.all(func(s):return not s.visible) and events==[0,0],"water begins with 緹娜's map cast lead, no prior projectile, future damage or fabricated duel")
	# 水剎 plays its effCode08 script (SkillEffectScriptPlayer): impact on the last drop batch,
	# completion at the script's end, in the cut-in's elapsed seconds after the cast lead.
	var timeline:Dictionary=clip.clips[0]["effect_timeline"]
	var tick_seconds:float=clip.Timing.PLAYBACK_SPEED/clip.skill_effects.TICKS_PER_SECOND
	var lead_in:float=clip.Timing.scaled(clip.OriginalTick.seconds(float(lead["complete_tick"])))
	var schedule:={"impact":lead_in+float(timeline["impact_tick"])*tick_seconds,"complete":lead_in+float(timeline["complete_tick"])*tick_seconds}
	clip._process(float(schedule["impact"])/clip.Timing.PLAYBACK_SPEED)
	check(events==[1,1] and clip.skill_effects.sprites.filter(func(s):return s.visible and str(s.texture.resource_path).contains("wat0")).size()>=2,"one water release/impact drives original WAT particles at both recipients")
	check(clip.skill_effects.sounds.any(func(player):return player.stream!=null and player.stream.resource_path.ends_with("water005.wav")),"water uses its own original sound, not wind/fire audio")
	clip._process(float(schedule["complete"])/clip.Timing.PLAYBACK_SPEED)
	check(not clip.busy() and not clip.skill_effects.visible and events==[1,1] and after==saved,"water completes once and never mutates the gameplay receipt")
	# This numerical renderer test advances clip time, not AudioServer wall time.
	# Explicitly stop its still-playing samples before tearing the fixture down.
	for audio in clip.find_children("*","AudioStreamPlayer",true,false):audio.stop();audio.stream=null
	root.remove_child(clip);clip.queue_free();await process_frame
	# Headless checks step presentation instantly; allow the real audio/render
	# servers to finish their asynchronous sample work before quitting the tree.
	await tree.create_timer(2.5).timeout

func large_and_equipment():
	var loop:=fixture()
	var giant:Dictionary=preload("res://tests/run_large_actor_tests.gd").source_large().duplicate(true)
	giant.merge({"id":"enemy021_1","coord":Vector2i(12,16),"hp":500,"max_hp":500},true)
	loop["units"]=loop["units"].filter(func(u):return u["battle_actor_role"]!=Loop.ROLE_ENEMY)
	loop["units"].append(giant)
	var before:=loop.duplicate(true)
	var after:=cast(loop,zero)
	check(Loop.Footprint.cells(giant).size()==9 and after["last_attack"]["affected_targets"].size()==1,"real source039 covering several cross cells takes exactly one target settlement")
	check(Loop.unit(after,"tina")["mp"]==Loop.unit(before,"tina")["mp"]-8 and Loop.unit(after,"enemy021_1")["hp"]==500-after["last_attack"]["actual_damage"],"large actor neither multiplies damage nor charges one cost per body cell")
	loop=fixture()
	var actor:=Loop._unit(loop,"tina")
	actor["equipment"]=actor["equipment"].filter(func(s):return s["slot"]!="accessory1")
	actor["equipment"].append({"slot":"accessory1","item_code":218})
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["mp"]=4
	after=cast(loop,zero)
	check(after["last_attack"]["resource_payment"]["amount"]==4 and after["last_attack"]["affected_targets"].size()==2 and Loop.unit(after,"tina")["mp"]==0,"current inverse-cross equipment halves the one cast debit, not each target")
	loop=fixture();loop["moved_this_action"]=true
	var calls:=[0]
	after=cast(loop,func(_bound):calls[0]+=1;return 0)
	check(calls[0]==0 and after["units"]==loop["units"],"unpermitted moved water casting is rejected without draws")
	actor=Loop._unit(loop,"tina")
	actor["equipment"]=actor["equipment"].filter(func(s):return s["slot"]!="accessory1")
	actor["equipment"].append({"slot":"accessory1","item_code":232})
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	check(cast(loop,zero)["last_attack"].get("skill_id")==WATER,"current movement ring permits the same water action after moving")
