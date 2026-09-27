extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const RepeatedSpecialRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const run_support_magic_tests = preload("res://tests/run_support_magic_tests.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


func _init() -> void:
	tag = "MOON_DANCE_TESTS"


static func fixture() -> Dictionary:
	var loop := run_support_magic_tests.priest_fixture()
	loop["tiles"] = {}
	var caster := BattlePlayLoop._unit(loop, "tina")
	caster["stamina"] = 60
	caster["hp"] = caster["max_hp"]
	caster["inventory"] = [227,228,232,233,244,241,248,0]
	var foe := BattlePlayLoop._unit(loop, "enemy021_1")
	foe["coord"] = Vector2i(11,16);foe["grid_coord"] = foe["coord"];foe["ai_home_coord"] = foe["coord"]
	foe["hp"] = 100;foe["max_hp"] = 100;foe["no_attack"] = false
	foe["inventory"] = [0,0,0,0,0,0,0,0]
	return BattlePlayLoop._return_to_player(loop,"tina")

static func selection(loop: Dictionary) -> Dictionary:
	var next := BattlePlayLoop.choose_command(loop, "special")
	return BattlePlayLoop.choose_special(next, RepeatedSpecialRules.ID) if next["interaction"] == "special_select" else next

func run() -> void:
	var boot := fixture()
	check(boot["scenario_ok"], "Moon initialization: " + str(boot.get("scenario_error", "")))
	if not boot["scenario_ok"]: return
	native_cases()
	multi_target_transaction()
	interaction_boundaries()

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
			var roll := BattlePlayLoop.SkillResolutionRules.Special.roll({"low":6,"high":12,"hit_ratio":int(case["hit"]),"attackpow_ratio":36,
				"level":int(case["level"]),"dex":int(case["dex"]),"mind":int(case["mind"]),"con":int(case["con"]),"hit_bonus":bonus,"no_attack":false},rng)
			var damage := mini(hp, int(roll["value"]))
			hp -= damage;bonus = int(roll["hit_bonus_after"])
			var basis := BattlePlayLoop.ExperienceRules.from_contribution(damage,int(case["level"]),int(case["target_level"]),hp,int(case["kill_exp"]),int(case["kill_word"]),rng)
			check(hp == int(result["native"]["hp"]) and damage == int(result["native"]["contribution"]) and bonus == int(result["native"]["hit_bonus"]), "original five-stage HP/miss/bonus including zero-HP tail")
			check(basis["points"] == int(result["native"]["experience"]) and cursor[0] == draws.size(), "original per-pulse EXP with unchanged prior kill chain")
	var base := fixture()
	check(BattlePlayLoop.special_options(base,"tina").size()==1 and BattlePlayLoop.special_options(base,"tina")[0]["id"]==RepeatedSpecialRules.ID,"002 source declaration now exposes only Moon Dance")
	check(BattlePlayLoop.special_options(BattleFixture.loop(),"leonard").all(func(o):return o["id"]!=RepeatedSpecialRules.ID),"default Leonard retains his own declared special")

func multi_target_transaction() -> void:
	var loop := fixture();var caster := BattlePlayLoop._unit(loop,"tina")
	caster["exp"] = 99;caster["kill_chain_word"] = 3
	var foe := BattlePlayLoop._unit(loop,"enemy021_1");foe["hp"] = 1
	var second := foe.duplicate(true);second["id"] = "moon_second";second["coord"] = Vector2i(9,15);second["grid_coord"] = second["coord"];second["ai_home_coord"] = second["coord"];second["hp"] = 25
	loop["units"].append(second)
	var third := foe.duplicate(true);third["id"] = "moon_third";third["coord"] = Vector2i(9,17);third["grid_coord"] = third["coord"];third["ai_home_coord"] = third["coord"];third["hp"] = 100
	loop["units"].append(third)
	var before := loop.duplicate(true)
	var selected := selection(loop)
	check(BattlePlayLoop.attack_cells(selected)==[caster["coord"]],"self-centered attack has exactly one selectable center")
	check(BattlePlayLoop.attack_coord(selected,foe["coord"],no_rng)["units"]==loop["units"],"clicking an enemy instead of self cannot secretly shift the area or pay")
	var result := BattlePlayLoop.attack_coord(selected,caster["coord"],zero)
	check(result["last_attack"].has("special_segments"),"self click commits a real repeated special")
	if not result["last_attack"].has("special_segments"): return
	var receipt: Dictionary = result["last_attack"]
	var parts: Array = receipt["special_segments"]
	check(parts.size()==15 and receipt["affected_targets"].size()==3,"one actor per target and five callbacks each")
	check(parts[0]["defender_id"]=="moon_second" and parts[5]["defender_id"]=="enemy021_1" and parts[10]["defender_id"]=="moon_third","coverage row-major target-major sequence survives reordered roster")
	check(BattlePlayLoop.unit(result,"enemy021_1")["defeated"] and BattlePlayLoop.unit(result,"moon_second")["defeated"] and not BattlePlayLoop.unit(result,"moon_third")["defeated"],"first-pulse/last-pulse kills and surviving target resolve together")
	check(parts[6]["silent_after_defeat"] and parts[9]["native_damage_roll"]["value"]>0 and parts[9]["damage"]==0,"zero-HP tail samples honestly without applying another kill")
	check(parts.all(func(p):return p["experience_basis"].get("kill_chain_before",3)==3),"later targets do not inherit prematurely increased kill chain")
	check(BattlePlayLoop.unit(result,"tina")["kill_count"]==2 and (int(BattlePlayLoop.unit(result,"tina")["kill_chain_word"])&0xffff)==4,"deferred death scan counts two victims and advances chain once")
	check(result["rewarded_unit_ids"].size()==2 and BattlePlayLoop.unit(result,"companion")["hp"]==BattlePlayLoop.unit(loop,"companion")["hp"],"unique kill rewards and allied exclusion")
	check(BattlePlayLoop.unit(result,"tina")["stamina"]==40 and parts.filter(func(p):return p["payment_applied"]).size()==1,"one payment across fifteen callbacks")
	var exp_sum := 0
	for part in parts: exp_sum += int(part["experience_basis"]["points"])
	check(receipt["experience_settlement"]["base"]==exp_sum and receipt["experience"]["gained"]==exp_sum,"all per-pulse contributions enter one final experience settlement")
	check(parts.all(func(p):return p["attacker_before"]["level"]==1) and BattlePlayLoop.unit(result,"tina")["level"]>1,"growth happens after all targets and snapshots hide final upgrade")
	check(loop==before and RepeatedSpecialRules.receipt_error(receipt)=="","atomic proposal leaves input unchanged and records consistent pulse chronology")
	check(BattleCheckpoint.encode(result,run_support_magic_tests.VIEW)["ok"],"quiet completed multi-target receipt roundtrips")
	var broken := result.duplicate(true);broken["last_attack"]["special_segments"][1]["defender_hp_before"]+=1
	check(not BattleCheckpoint.encode(broken,run_support_magic_tests.VIEW)["ok"],"save rejects a contradictory intermediate HP sequence")

func interaction_boundaries() -> void:
	var loop := fixture()
	own(loop, "equipment_items")["82"]["weapon_effect_flags"] = 0x210000 # Synthetic ordinary-only flags, never a source staff grant.
	own(loop, "skill_book")["actors"]["002"]["double_attack"] = true
	own(loop, "skill_book")["actors"]["021"]["double_attack"] = true
	var defender := BattlePlayLoop._unit(loop,"enemy021_1")
	defender["combat_profile"]["attack_back"] = 100
	for kind in ["poison","paralysis","no_magic"]:
		defender.merge(BattlePlayLoop.StatusEffectRules.apply(defender,kind,2,2 if kind=="poison" else 0)["changes"],true)
	var before := loop.duplicate(true)
	var result := BattlePlayLoop.attack_coord(selection(loop),BattlePlayLoop.unit(loop,"tina")["coord"],zero)
	check(result["last_attack"]["special_segments"].size()==5 and result["last_attack"]["counter"].is_empty(),"ordinary double/counter rules do not multiply or interrupt Moon callbacks")
	check(BattlePlayLoop.unit(result,"tina")["hp"]==BattlePlayLoop.unit(before,"tina")["hp"] and BattlePlayLoop.unit(result,"enemy021_1")["status_counters"]==defender["status_counters"],"Moon does not trigger ordinary poison/cancellation or cure the target's existing states")
	check(result["last_attack"]["special_segments"].all(func(p):return not p.has("weapon_aftereffects")),"special receipts contain no ordinary-series aftereffect")
	for change in ["dead","resources"]:
		var pending := selection(fixture())
		if change=="dead": BattlePlayLoop._set_unit_defeated(pending,"enemy021_1",true)
		else: BattlePlayLoop._unit(pending,"tina")["stamina"]=19
		var rejected := BattlePlayLoop.attack_coord(pending,BattlePlayLoop.unit(pending,"tina")["coord"],no_rng)
		check(rejected["units"]==pending["units"] and rejected["turn_queue"]==pending["turn_queue"],"confirmation rechecks current state without stale preview effects: "+change)
	var scenario := BattlePlayLoop.BattleScenario.load_file("res://content/battles/moon_dance_trial.json")
	var trial := BattlePlayLoop.create([],"",scenario)
	check(trial["scenario_ok"] and BattlePlayLoop.CoreTurnQueue.current(trial["turn_queue"])["id"]=="tina","published surrounding-enemy practice gives a real first player action")
	for unit in trial["units"]:
		check(BattlePlayLoop.TraversalRules.placement_error(unit,trial["units"],trial["tiles"],trial["map_size"])=="","published practice actors occupy actual original walkable ground")
