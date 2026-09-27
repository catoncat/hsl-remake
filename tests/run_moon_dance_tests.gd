extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const Moon = preload("res://game/sim/RepeatedSpecialRules.gd")
const Priests = preload("res://tests/run_support_magic_tests.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


func _init() -> void:
	tag = "MOON_DANCE_TESTS"


static func fixture() -> Dictionary:
	var loop := Priests.priest_fixture()
	loop["tiles"] = {}
	var caster := Loop._unit(loop, "tina")
	caster["stamina"] = 60
	caster["hp"] = caster["max_hp"]
	caster["inventory"] = [227,228,232,233,244,241,248,0]
	var foe := Loop._unit(loop, "enemy021_1")
	foe["coord"] = Vector2i(11,16);foe["grid_coord"] = foe["coord"];foe["ai_home_coord"] = foe["coord"]
	foe["hp"] = 100;foe["max_hp"] = 100;foe["no_attack"] = false
	foe["inventory"] = [0,0,0,0,0,0,0,0]
	return Loop._return_to_player(loop,"tina")

static func selection(loop: Dictionary) -> Dictionary:
	var next := Loop.choose_command(loop, "special")
	return Loop.choose_special(next, Moon.ID) if next["interaction"] == "special_select" else next

func run() -> void:
	var boot := fixture()
	check(boot["scenario_ok"], "Moon initialization: " + str(boot.get("scenario_error", "")))
	if not boot["scenario_ok"]: return
	native_cases()
	multi_target_transaction()
	qualification_and_restore()
	interaction_boundaries()
	ai_and_outcomes()
	presentation_known_mask()

## The dedicated presenter builds its own shot per target; the cut-in strip's 0x434d10 mask
## (BattleCombatCutin._show_shot reads clip["known"]) must hold for a 月花圓舞 target the
## player has not fought (R34: the chapter walk's first 53-win hit a missing key here).
func presentation_known_mask() -> void:
	var loop := fixture();var caster := Loop._unit(loop,"tina");caster["kill_chain_word"] = 3
	var foe := Loop._unit(loop,"enemy021_1");foe["hp"] = 100
	var result := Loop.attack_coord(selection(loop),caster["coord"],zero)
	check(result["last_attack"].has("special_segments"),"presentation fixture commits a repeated special")
	if not result["last_attack"].has("special_segments"): return
	var view = preload("res://game/battle/scene/BattleCombatCutin.gd").new()
	root.add_child(view);view.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json");view.set_process(false)
	var known := {"tina": true, "enemy021_1": false}
	view.play(result["last_attack"],Loop.unit(result,"tina"),Loop.unit(result,"enemy021_1"),false,Vector2(320,240),Vector2(240,240),[],result["units"],known)
	var presenter = view._presenter(view.clips[0])
	check(presenter != null and presenter.get_script().resource_path.ends_with("MoonDancePresentation.gd"),"月花圓舞 routes to its dedicated presenter")
	if presenter == null: view.free();return
	var clip: Dictionary = view.clips[0]
	check(clip["known"] == known,"the clip carries the known map for every participant")
	presenter.present(view, clip, presenter.intro + 0.01) # first target shot, before its first pulse
	check(view.vitals.values["hp"].text == "???" and view.vitals.values["level"].text == "??","an unknown 月花圓舞 target keeps the ??? strip through the presenter's own shot")
	var seen: Dictionary = view.clips[0].duplicate(true);seen["known"] = {"tina": true, "enemy021_1": true}
	presenter.present(view, seen, presenter.intro + 0.01)
	check(view.vitals.values["hp"].text != "???","a fought target's HP is readable in the same shot")
	presenter.reset();view.free()

func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_moon_dance.json"))
	for row in packet["cases"]:
		var case: Dictionary = row["input"]
		var hp := int(case["hp"]);var bonus := 0
		for result in row["results"]:
			var cursor := [0]
			var draws: Array = result["draws"]
			var rng := func(bound: int) -> int:
				check(cursor[0] < draws.size(), "original pulse has no extra random call")
				if cursor[0] >= draws.size(): return 0
				var draw: Dictionary = draws[cursor[0]];cursor[0] += 1
				check(bound == int(draw["bound"]), "damage and contribution random bounds stay in native order")
				return int(draw["value"])
			var roll := Loop.SkillResolutionRules.Special.roll({"low":6,"high":12,"hit_ratio":int(case["hit"]),"attackpow_ratio":36,
				"level":int(case["level"]),"dex":int(case["dex"]),"mind":int(case["mind"]),"con":int(case["con"]),"hit_bonus":bonus,"no_attack":false},rng)
			var damage := mini(hp, int(roll["value"]))
			hp -= damage;bonus = int(roll["hit_bonus_after"])
			var basis := Loop.ExperienceRules.from_contribution(damage,int(case["level"]),int(case["target_level"]),hp,int(case["kill_exp"]),int(case["kill_word"]),rng)
			check(hp == int(result["native"]["hp"]) and damage == int(result["native"]["contribution"]) and bonus == int(result["native"]["hit_bonus"]), "original five-stage HP/miss/bonus including zero-HP tail")
			check(basis["points"] == int(result["native"]["experience"]) and cursor[0] == draws.size(), "original per-pulse EXP with unchanged prior kill chain")
	var base := fixture()
	check(Loop.special_options(base,"tina").size()==1 and Loop.special_options(base,"tina")[0]["id"]==Moon.ID,"002 source declaration now exposes only Moon Dance")
	check(Loop.special_options(BattleFixture.loop(),"leonard").all(func(o):return o["id"]!=Moon.ID),"default Leonard retains his own declared special")

func multi_target_transaction() -> void:
	var loop := fixture();var caster := Loop._unit(loop,"tina")
	caster["exp"] = 99;caster["kill_chain_word"] = 3
	var foe := Loop._unit(loop,"enemy021_1");foe["hp"] = 1
	var second := foe.duplicate(true);second["id"] = "moon_second";second["coord"] = Vector2i(9,15);second["grid_coord"] = second["coord"];second["ai_home_coord"] = second["coord"];second["hp"] = 25
	loop["units"].append(second)
	var third := foe.duplicate(true);third["id"] = "moon_third";third["coord"] = Vector2i(9,17);third["grid_coord"] = third["coord"];third["ai_home_coord"] = third["coord"];third["hp"] = 100
	loop["units"].append(third)
	var before := loop.duplicate(true)
	var selected := selection(loop)
	check(Loop.attack_cells(selected)==[caster["coord"]],"self-centered attack has exactly one selectable center")
	check(Loop.attack_coord(selected,foe["coord"],no_rng)["units"]==loop["units"],"clicking an enemy instead of self cannot secretly shift the area or pay")
	var result := Loop.attack_coord(selected,caster["coord"],zero)
	check(result["last_attack"].has("special_segments"),"self click commits a real repeated special")
	if not result["last_attack"].has("special_segments"): return
	var receipt: Dictionary = result["last_attack"]
	var parts: Array = receipt["special_segments"]
	check(parts.size()==15 and receipt["affected_targets"].size()==3,"one actor per target and five callbacks each")
	check(parts[0]["defender_id"]=="moon_second" and parts[5]["defender_id"]=="enemy021_1" and parts[10]["defender_id"]=="moon_third","coverage row-major target-major sequence survives reordered roster")
	check(Loop.unit(result,"enemy021_1")["defeated"] and Loop.unit(result,"moon_second")["defeated"] and not Loop.unit(result,"moon_third")["defeated"],"first-pulse/last-pulse kills and surviving target resolve together")
	check(parts[6]["silent_after_defeat"] and parts[9]["native_damage_roll"]["value"]>0 and parts[9]["damage"]==0,"zero-HP tail samples honestly without applying another kill")
	check(parts.all(func(p):return p["experience_basis"].get("kill_chain_before",3)==3),"later targets do not inherit prematurely increased kill chain")
	check(Loop.unit(result,"tina")["kill_count"]==2 and (int(Loop.unit(result,"tina")["kill_chain_word"])&0xffff)==4,"deferred death scan counts two victims and advances chain once")
	check(result["rewarded_unit_ids"].size()==2 and Loop.unit(result,"companion")["hp"]==Loop.unit(loop,"companion")["hp"],"unique kill rewards and allied exclusion")
	check(Loop.unit(result,"tina")["stamina"]==40 and parts.filter(func(p):return p["payment_applied"]).size()==1,"one payment across fifteen callbacks")
	var exp_sum := 0
	for part in parts: exp_sum += int(part["experience_basis"]["points"])
	check(receipt["experience_settlement"]["base"]==exp_sum and receipt["experience"]["gained"]==exp_sum,"all per-pulse contributions enter one final experience settlement")
	check(parts.all(func(p):return p["attacker_before"]["level"]==1) and Loop.unit(result,"tina")["level"]>1,"growth happens after all targets and snapshots hide final upgrade")
	check(loop==before and Moon.receipt_error(receipt)=="","atomic proposal leaves input unchanged and records consistent pulse chronology")
	check(Save.encode(result,Priests.VIEW)["ok"],"quiet completed multi-target receipt roundtrips")
	var broken := result.duplicate(true);broken["last_attack"]["special_segments"][1]["defender_hp_before"]+=1
	check(not Save.encode(broken,Priests.VIEW)["ok"],"save rejects a contradictory intermediate HP sequence")

func qualification_and_restore() -> void:
	var loop := fixture();var actor := Loop._unit(loop,"tina")
	actor["mp"] = 0;actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	var walk := Loop.move_unit_to(Loop.choose_command(loop,"move"),Vector2i(11,17))
	check(walk["pending_move"] and Loop.command_available(walk,"special") and not Loop.command_available(walk,"magic"),"special remains legal after movement with zero MP and silence")
	var cancel := Loop.cancel_interaction(selection(walk))
	check(cancel["units"]==walk["units"] and cancel["pending_move"],"cancel target selection preserves pending movement and all resources")
	var restored := Loop.cancel_interaction(Loop.cancel_pending_move(cancel))
	check(Loop.unit(restored,"tina")["coord"]==actor["coord"] and not restored["moved_this_action"],"movement cancellation restores exact phase")
	var encoded := Save.encode(restored,Priests.VIEW)
	check(encoded["ok"] and Save.decode(encoded["bytes"], restored)["snapshot"]["loop"]==restored,"saved phase has current ownership without additional resources")
	var wings := Priests.equip(fixture(),"accessory2",227)
	var first := Loop.attack_coord(selection(wings),Loop.unit(wings,"tina")["coord"],zero)
	first = Loop.finish_exhausted_action(first)
	check(first["extra_action"]["pending"] and Loop.unit(first,"tina")["stamina"]==40,"completed five pulses lead to one independent second action")
	var second := Loop.attack_coord(selection(first),Loop.unit(first,"tina")["coord"],zero)
	check(second["last_attack"]["special_segments"].size()==5 and Loop.unit(second,"tina")["stamina"]==20,"second action pays separately and does not multiply the five-pulse program")
	var both := fixture();own(both, "skill_book")["actors"]["002"]["supported_initial_ids"].append("special:magicOTHER:magicCode01")
	var chooser := Loop.choose_command(both,"special")
	check(chooser["interaction"]=="special_select" and Loop.choose_special(chooser,Moon.ID)["selected_skill_id"]==Moon.ID,"multiple owned specials have an actual choice without replacing existing Qi Blade")
	for kind in ["resource","paralysis","empty","unowned","bad_target"]:
		var invalid := fixture()
		var source := Loop._unit(invalid,"tina")
		if kind=="resource": source["stamina"]=19
		elif kind=="paralysis": source.merge(Loop.StatusEffectRules.apply(source,"paralysis",2)["changes"],true)
		elif kind=="empty": Loop._unit(invalid,"enemy021_1")["coord"]=Vector2i(18,20)
		elif kind=="unowned": own(invalid, "skill_book")["actors"]["002"]["supported_initial_ids"]=[Priests.HEAL]
		else: Loop._unit(invalid,"enemy021_1")["status_counters"].erase("poison")
		var rejected := Loop.attack_coord(selection(invalid),source["coord"],no_rng)
		check(rejected["units"]==invalid["units"] and rejected["turn_queue"]==invalid["turn_queue"],"failed cast is atomic with no RNG: "+kind)

func interaction_boundaries() -> void:
	var loop := fixture()
	own(loop, "equipment_items")["82"]["weapon_effect_flags"] = 0x210000 # Synthetic ordinary-only flags, never a source staff grant.
	own(loop, "skill_book")["actors"]["002"]["double_attack"] = true
	own(loop, "skill_book")["actors"]["021"]["double_attack"] = true
	var defender := Loop._unit(loop,"enemy021_1")
	defender["combat_profile"]["attack_back"] = 100
	for kind in ["poison","paralysis","no_magic"]:
		defender.merge(Loop.StatusEffectRules.apply(defender,kind,2,2 if kind=="poison" else 0)["changes"],true)
	var before := loop.duplicate(true)
	var result := Loop.attack_coord(selection(loop),Loop.unit(loop,"tina")["coord"],zero)
	check(result["last_attack"]["special_segments"].size()==5 and result["last_attack"]["counter"].is_empty(),"ordinary double/counter rules do not multiply or interrupt Moon callbacks")
	check(Loop.unit(result,"tina")["hp"]==Loop.unit(before,"tina")["hp"] and Loop.unit(result,"enemy021_1")["status_counters"]==defender["status_counters"],"Moon does not trigger ordinary poison/cancellation or cure the target's existing states")
	check(result["last_attack"]["special_segments"].all(func(p):return not p.has("weapon_aftereffects")),"special receipts contain no ordinary-series aftereffect")
	for change in ["dead","resources"]:
		var pending := selection(fixture())
		if change=="dead": Loop._set_unit_defeated(pending,"enemy021_1",true)
		else: Loop._unit(pending,"tina")["stamina"]=19
		var rejected := Loop.attack_coord(pending,Loop.unit(pending,"tina")["coord"],no_rng)
		check(rejected["units"]==pending["units"] and rejected["turn_queue"]==pending["turn_queue"],"confirmation rechecks current state without stale preview effects: "+change)
	var scenario := Loop.BattleScenario.load_file("res://content/battles/moon_dance_trial.json")
	var trial := Loop.create([],"",scenario)
	check(trial["scenario_ok"] and Loop.CoreTurnQueue.current(trial["turn_queue"])["id"]=="tina","published surrounding-enemy practice gives a real first player action")
	for unit in trial["units"]:
		check(Loop.TraversalRules.placement_error(unit,trial["units"],trial["tiles"],trial["map_size"])=="","published practice actors occupy actual original walkable ground")


func ai_and_outcomes() -> void:
	var ai := fixture();var actor := Loop._unit(ai,"tina")
	actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
	ai["interaction"]="ai_resolving";ai["selected_unit_id"]=""
	Loop._unit(ai,"enemy021_1")["coord"]=Vector2i(14,16)
	own(ai, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_special":100},true)
	var prepared := LoopAI._prepare_ai_turn(ai,"tina")
	check(prepared["ok"],"AI self-centered candidate search is valid: "+str(prepared.get("reason","")))
	var acted := Loop.step_ai_turn(ai,zero)
	check(acted["scenario_ok"] and acted["last_ai_action"].get("skill_id")==Moon.ID and acted["last_ai_action"]["kind"]=="move_then_attack","AI moves to an actual area anchor and casts its owned special")
	check(acted["last_combat"].get("special_segments",[]).size()==5 and Loop.unit(acted,"tina")["stamina"]==40,"AI shares the five-stage transaction and one resource payment")
	for outcome in ["victory","defeat","escape"]:
		var loop := fixture();var source := Loop._unit(loop,"tina")
		if outcome=="victory":
			Loop._unit(loop,"enemy021_1")["hp"]=1
			loop=Loop.attack_coord(selection(loop),source["coord"],zero)
		elif outcome=="escape":
			Loop._set_unit_coord(loop,"tina",loop["escape_zone"][0]);loop=Loop.choose_command(loop,"wait")
		else:
			source["hp"]=1
			var foe:=Loop._unit(loop,"enemy021_1");foe["hit_bonus_accum"]=1000;foe["combat_profile"]["attack_back"]=100;foe["combat_profile"]["live_attack_damage"]=1000
			loop=Loop.attack_target(Loop.choose_command(loop,"attack"),foe["id"],zero)
		check(BattleOutcome.decided(loop) and Save.encode(loop,Priests.VIEW)["ok"],"special-capable priest terminal/checkpoint: "+outcome)
		check(Loop.step_ai_turn(loop,no_rng)==loop and Loop.finish_exhausted_action(loop)==loop,"terminal blocks more callbacks: "+outcome)
