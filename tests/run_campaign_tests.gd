extends SceneTree

## Campaign hand-off between battles: carry capture/apply through the shared
## PlayLoop seam, and the runtime flow from a victory result page into the next
## scenario's product opening with the carried party.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const WorldPartyRules = preload("res://game/world/WorldPartyRules.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit in loop.get("units", []):
		if str(unit.get("id", "")) == unit_id:
			return unit
	return {}


func _run() -> void:
	_test_pure_carry()
	_test_town_job_up_carry()
	_test_battle_job_up_carry()
	_test_destinations()
	await _test_battle_job_up_runtime_handoff()
	await _test_separate_party_loot_gate()
	await _test_saved_progress()
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await process_frame
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("CAMPAIGN_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("CAMPAIGN_TESTS_FAIL count=%d" % failures.size())
		quit(1)


## next_level_event [level, event] follows the original scripts' reading
## (tools/hsltools/data/big_map_flow.py, `hsl generate big_map_flow`): event = the level whose script set runs next,
## gameBigMapLevel (49) = back to the big map at point <level>; a battle whose
## script sets no next level returns to the map at its own point.
func _test_destinations() -> void:
	var campaign := CampaignProgress.load_campaign()
	var world_map_path := "res://content/world/world_map_scene.json"
	_assert_eq(CampaignProgress.next_scenario_path(campaign, {"next_level_event": [52, 52]}), "res://content/battles/battle_052.json", "[52, 52] enters level 52")
	_assert_eq(CampaignProgress.next_scenario_path(campaign, {"next_level_event": [53, 1]}), "res://content/battles/ohm_village_battle.json", "the second value names the playable level to load ([53, 1] → Ohm Village)")
	_assert_eq(CampaignProgress.next_scenario_path(campaign, {"next_level_event": [2, 55]}), "res://content/battles/story_055.json", "WINFAIL002's [2, 55] enters the camp story level 55")
	_assert_eq(CampaignProgress.next_scenario_path(campaign, {"next_level_event": [2, 14]}), "", "an unregistered level (14, no script) resolves to no path")
	var to_map := CampaignProgress.next_destination(campaign, {"next_level_event": [10, 49]})
	_assert_eq([str(to_map.get("kind", "")), str(to_map.get("path", "")), int(to_map.get("point", 0)), bool(to_map.get("default_return", true))], ["world_map", world_map_path, 10, false], "[10, gameBigMapLevel] returns to the big map at point 10")
	_assert_true(CampaignProgress.next_destination(campaign, {}, "res://content/battles/battle_051.json").is_empty(), "level 51 (prologue, not a map point) with no next level ends the chapter as before")
	var synthetic := {"schema": "hsl_campaign.v1", "battles": {"5": {"scenario": "res://synthetic/level_005.json", "title": "呼嘯平原"}}, "world_map": campaign["world_map"]}
	var own := CampaignProgress.next_destination(synthetic, {}, "res://synthetic/level_005.json")
	_assert_eq([str(own.get("kind", "")), int(own.get("point", 0)), bool(own.get("default_return", false))], ["world_map", 5, true], "a map-point level with no next level (WINFAIL005) returns to the map at its own point")
	_assert_true(CampaignProgress.next_destination({"battles": synthetic["battles"]}, {}, "res://synthetic/level_005.json").is_empty(), "without a registered world map the default return does not exist")
	_assert_eq(CampaignProgress.level_key_for_scenario(campaign, "res://content/battles/battle_053.json"), 53, "level key lookup by scenario path")
	_assert_true(CampaignProgress.level_is_map_point(campaign, 45) and not CampaignProgress.level_is_map_point(campaign, 46), "point_level_range covers bigmap.dat ids 1–45")


func _test_pure_carry() -> void:
	var campaign := CampaignProgress.load_campaign()
	_assert_eq(str(campaign.get("schema", "")), "hsl_campaign.v1", "campaign.json should load")
	_assert_eq(str(campaign["battles"]["52"]["scenario"]), "res://content/battles/battle_052.json", "level 52 maps to the second battle scenario")

	var first := BattleFixture.loop([], "", 7)
	_assert_true(bool(first.get("scenario_ok", false)), "first battle loop should be valid")
	var leonard := _unit(first, "leonard")
	var template_max_hp := int(leonard["max_hp"])
	leonard["level"] = 3
	leonard["exp"] = 40
	leonard["pending_stat_points"] = 2
	leonard["kill_count"] = 4
	leonard["combat_profile"]["str"] = int(leonard["combat_profile"]["str"]) + 3
	leonard["combat_profile"]["con"] = int(leonard["combat_profile"]["con"]) + 2
	var consumable_code := int(str(first["consumables"].keys()[0]))
	leonard["inventory"] = [consumable_code, consumable_code, 0, 0, 0, 0, 0, 0]
	leonard["hp"] = 1
	first["gold"] = 120
	first["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	first["scenario_id"] = "battle_051_cannon_fodder"
	first["next_level_event"] = [52, 52] # the fixture carries no script; WINFAIL051's hand-off is asserted on battle_051 in run_tests
	_assert_eq(CampaignProgress.next_scenario_path(campaign, first), "res://content/battles/battle_052.json", "next scenario resolves from next_level_event")

	var carry := CampaignCarryRules.capture(first, campaign["carry_policy"])
	_assert_eq(carry["schema"], "hsl_campaign_carry.v1", "carry schema")
	_assert_true(carry["units"].has("leonard") and not carry["units"].has("enemy021_1"), "only controlled units are carried")
	_assert_eq(int(carry["units"]["leonard"]["level"]), 3, "carried level")
	_assert_eq(int(carry["units"]["leonard"]["attributes"]["str"]), int(leonard["combat_profile"]["str"]), "carried str attribute")
	_assert_eq(int(carry["loop"]["gold"]), 120, "carried gold")

	var second := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_052.json"), 7)
	_assert_true(bool(second.get("scenario_ok", false)), "second battle loop should be valid")
	var boss_hp := int(_unit(second, "emperor025")["hp"])
	var applied := BattlePlayLoop.apply_campaign_carry(second, carry)
	var carried := _unit(applied, "leonard")
	_assert_eq(int(carried["level"]), 3, "level applied")
	_assert_eq(int(carried["exp"]), 40, "exp applied")
	_assert_eq(int(carried["pending_stat_points"]), 2, "unspent points applied")
	_assert_eq(int(carried["kill_count"]), 4, "kill count applied")
	_assert_eq(int(carried["combat_profile"]["str"]), int(leonard["combat_profile"]["str"]), "str applied")
	_assert_eq(carried["inventory"], [consumable_code, consumable_code, 0, 0, 0, 0, 0, 0], "inventory applied")
	_assert_true(int(carried["max_hp"]) > template_max_hp, "refreshed max HP should grow with level and constitution")
	_assert_eq(int(carried["hp"]), int(carried["max_hp"]), "HP restores to the refreshed maximum")
	_assert_eq(int(carried["stamina"]), 0, "a carried member enters at 0 ST (0x407632), not the PLAYERS template's 20")
	_assert_eq(int(applied["gold"]), 120, "gold applied to the new loop")
	_assert_eq(int(_unit(applied, "emperor025")["hp"]), boss_hp, "other units untouched")
	_assert_eq(applied["campaign_carry_receipt"]["applied_unit_ids"], ["leonard"], "receipt lists the carried unit")
	_assert_eq(applied["campaign_carry_receipt"]["errors"], [], "no carry errors")
	_assert_eq(str(applied.get("interaction", "")), "idle", "carry does not start the battle")
	var queue_ids: Array = []
	for slot in applied["turn_queue"].get("slots", []):
		queue_ids.append(str(slot.get("id", "")))
	_assert_true(queue_ids.has("leonard") and queue_ids.size() == 18, "queue rebuilt with the whole roster (18 incl. the two 069)")

	var untouched := BattlePlayLoop.apply_campaign_carry(second, {})
	_assert_eq(untouched.get("campaign_carry_receipt", {}), {}, "empty carry is a no-op")
	var started := BattlePlayLoop.begin_battle(second)
	var late := BattlePlayLoop.apply_campaign_carry(started, carry)
	_assert_eq(int(_unit(late, "leonard")["level"]), int(_unit(second, "leonard")["level"]), "carry after begin_battle is refused")
	var mismatch := carry.duplicate(true)
	mismatch["units"]["leonard"]["actor_id"] = "999"
	var refused := BattlePlayLoop.apply_campaign_carry(second, mismatch)
	_assert_eq(refused["campaign_carry_receipt"]["skipped_unit_ids"], ["leonard"], "actor mismatch is skipped explicitly")


## 命運神殿 job-up (TownEventRules teCheckJobUp → WorldPartyRules.apply_party) leaves
## a job_up_history on the carry member; the next battle replays it onto the base
## template (JobUpRules.merge_source_template: job 80 → 81, additive PLAYERS layer,
## move point, same actor id / equipment / learned skills) before the carry values.
func _test_town_job_up_carry() -> void:
	var campaign := CampaignProgress.load_campaign()
	var first := BattleFixture.loop([], "", 7)
	var leonard := _unit(first, "leonard")
	leonard["level"] = 12
	leonard["combat_profile"]["str"] = 40
	leonard["combat_profile"]["dex"] = 38
	leonard["combat_profile"]["mind"] = 30
	leonard["combat_profile"]["con"] = 44
	first["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	var carry := CampaignCarryRules.capture(first, campaign["carry_policy"])
	var speakers := {"SID_雷歐納德": {"players_row": 1, "name_text": "雷歐納德"}}
	var before := WorldPartyRules.party_from_carry(carry, speakers)
	_assert_eq(before["member_records"]["SID_雷歐納德"]["attributes"], {"str": 40, "dex": 38, "mind": 30, "con": 44}, "town party view exposes the member attributes")
	var towndef := TownEventRules.load_towndef("res://content/imported/hsl/global/world_map/towndef.json")
	var state := {"schema": "hsl_world_state.v1", "towns": TownEventRules.initial_town_state(towndef, TownEventRules.load_initial_trees("res://content/world/town_initial_trees.json"))}
	var run := TownEventRules.begin_event(state, before, towndef, 16, 61)
	_assert_eq((run["effects"][1] as Dictionary).get("kind"), "job_up", "神殿 event 61 upgrades 雷歐納德")
	var applied := WorldPartyRules.apply_party(carry, before, run["party"])
	_assert_eq((applied["receipt"]["job_ups"] as Array).size(), 1, "apply_party writes one job-up back")
	var next_carry: Dictionary = applied["carry"]
	_assert_eq(str(next_carry["units"]["leonard"]["job_up_target_actor_id"]), "010", "carry member stands on 010")
	_assert_eq(str(next_carry["units"]["leonard"]["actor_id"]), "001", "actor id stays the resource key")
	var second := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_052.json"), 7)
	var base := _unit(second, "leonard")
	var fielded := BattlePlayLoop.apply_campaign_carry(second, next_carry)
	var unit := _unit(fielded, "leonard")
	_assert_eq(fielded["campaign_carry_receipt"]["errors"], [], "job-up carry applies without errors")
	_assert_eq(fielded["campaign_carry_receipt"].get("job_up_replayed_unit_ids", []), ["leonard"], "receipt names the replayed unit")
	_assert_eq([int(unit["growth_profile"]["job_code"]), unit["growth_profile"]["caps"]], [81, {"str": 130, "dex": 112, "mind": 100, "con": 110}], "job 81 劍豪 with its cap row")
	_assert_eq([str(unit["actor_id"]), str(unit["job_up_target_actor_id"]), int(unit["job_up_flags"])], ["001", "010", 0x80000000], "same actor id, target 010, native flag")
	_assert_eq(int(unit["level"]), 12, "level carried")
	_assert_eq(int(unit["combat_profile"]["str"]), 40, "attributes carried, not replaced by the template")
	_assert_eq(unit["equipment"], base["equipment"], "010 declares no equipment: gear stays")
	_assert_eq(int(unit["base_move_point"]), int(base["base_move_point"]) + 1, "0x4348f0 adds the target move point (010: 1)")
	_assert_eq(int(unit["growth_profile"]["source"]["hit_point"]), int(base["growth_profile"]["source"]["hit_point"]) + 50, "additive PLAYERS layer: 010 hit_point 50")
	_assert_eq(int(unit["growth_profile"]["source"]["attack_power"]), int(base["growth_profile"]["source"]["attack_power"]) + 40, "additive PLAYERS layer: 010 attack_power 40")
	var same_level := base.duplicate(true)
	same_level["level"] = 12
	for key in ["str", "dex", "mind", "con"]:
		same_level["combat_profile"][key] = unit["combat_profile"][key]
	var reference := BattlePlayLoop.ProgressionRules.refresh_growth_stats(same_level, second["equipment_items"])
	_assert_true(int(unit["max_hp"]) > int(reference["max_hp"]) and int(unit["combat_profile"]["live_magic_attack"]) >= int(reference["combat_profile"]["live_magic_attack"]) + 30, "劍豪 refresh: +50 HP layer and the +30 magic branch bonus over a same-level 劍士")
	_assert_eq(int(unit["hp"]), int(unit["max_hp"]), "vitals restored on the refreshed maximum")
	var roundtrip := CampaignCarryRules.capture(fielded, campaign["carry_policy"])
	_assert_eq(roundtrip["units"]["leonard"]["job_up_history"], next_carry["units"]["leonard"]["job_up_history"], "the history survives the next capture")
	var third := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_052.json"), 7)
	var again := BattlePlayLoop.apply_campaign_carry(third, roundtrip)
	_assert_eq(int(_unit(again, "leonard")["growth_profile"]["source"]["hit_point"]), int(unit["growth_profile"]["source"]["hit_point"]), "replay is idempotent across battles (no double accumulation)")


## The 咕嚕 chain across hand-offs: a carry holding 咕嚕 008 fields the conditional (有才產生)
## slot of level 37, WINFAIL037 event 48 (咕嚕 attacks the 052 guardian → actPlayerJobUpProcess)
## merges the 017 template like a town job-up (actor id stays 008, job_up_history records
## 017 — the row 008's job_up_code resolves to, original_level37_tokens.md), keeps his current
## HP, and the next battle's conditional slot fields the member again and replays the 017
## form from the carry — the same contract as _test_town_job_up_carry.
func _test_battle_job_up_carry() -> void:
	var Conditional = preload("res://game/sim/ConditionalPartyRules.gd")
	var Winfail = preload("res://game/sim/WinfailScenarioRules.gd")
	var ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
	var campaign := CampaignProgress.load_campaign()
	var panels: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/shared/panels/manifest.json"))["actors"]
	# A carry holding every slot: an encounter launched without a hand-off fields all nine.
	var encounter := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_540.json"), 7)
	var recruit := _unit(encounter, "gulu")
	recruit["level"] = 4
	recruit["kill_count"] = 3
	recruit["pending_stat_points"] = 5
	encounter["battle_outcome"] = BattleOutcome.VICTORY_ENEMIES_CLEARED
	var carry := CampaignCarryRules.capture(encounter, campaign["carry_policy"])
	_assert_eq(str(carry["units"]["gulu"]["actor_id"]), "008", "the carry holds 咕嚕 008")
	var scenario37 := BattleScenario.load_file("res://content/battles/battle_037.json")
	var conditional := Conditional.apply(scenario37, carry)
	_assert_eq([str(conditional["receipt"]["mode"]), conditional["receipt"]["installed"], conditional["receipt"]["skipped"]], ["install_if_carried", ["gulu"], []], "level 37 fields the carried 咕嚕 through its EVEF 有才產生 slot")
	var without := Conditional.apply(scenario37, CampaignCarryRules.capture(BattleFixture.loop([], "", 7), campaign["carry_policy"]))
	_assert_eq(without["receipt"]["skipped"], ["gulu"], "a party without 咕嚕 enters level 37 without the slot")
	var level37 := BattlePlayLoop.apply_campaign_carry(BattlePlayLoop.create([], "", conditional["scenario"], 7), carry)
	_assert_eq(level37["campaign_carry_receipt"]["errors"], [], "the carry applies to level 37 without errors")
	var gulu := _unit(level37, "gulu")
	_assert_eq([str(gulu["actor_id"]), gulu["coord"], int(gulu["level"]), int(gulu["growth_profile"]["job_code"])], ["008", Vector2i(12, 35), 4, 96], "咕嚕 stands on his STORY037 endpoint (EVEF 384,1312 walked -192) with the carried level")
	_assert_eq(str(level37["winfail_runtime"]["actor_bindings"].get("SID_咕嚕/1", "")), "gulu", "the winfail tokens resolve SID_咕嚕 to the fielded slot")
	# WINFAIL037 inserts the 052 guardian later; stand it next to 咕嚕 and let him attack it.
	var guardian: Dictionary = (level37["script_actor_source"]["templates"]["obj_Story_Level_Enemy52"]["actor"] as Dictionary).duplicate(true)
	guardian["coord"] = Vector2i(13, 35)
	level37["units"].append(guardian)
	level37["event_statuses"] = [48]
	gulu["hp"] = 7  # wounded: 0x4348f0 / 0x407ec0 / 0x448840 write no vitals
	level37["last_attack"] = {"attacker_id": "gulu", "defender_id": str(guardian["id"])}
	level37 = Winfail.run_event_hooks(level37, true)
	_assert_eq(level37["winfail_runtime"]["fired"].map(func(entry): return str(entry.get("key", ""))), ["event_48"], "event 48 fires when 咕嚕 attacks the 052 guardian")
	_assert_eq(level37["winfail_runtime"]["unsupported_encountered"], [], "the level 37 job-up runs with no unsupported action")
	gulu = _unit(level37, "gulu")
	_assert_eq([str(gulu["actor_id"]), str(gulu["job_up_target_actor_id"]), int(gulu["growth_profile"]["job_code"]), int(gulu["weapon_code"]), int(gulu["level"]), int(gulu["kill_count"])], ["008", "017", 97, 53, 4, 3], "actPlayerJobUpProcess stands 咕嚕 on 017 (job 97 jobEvilMonster, weapon 53) and keeps his record")
	_assert_eq(int(gulu["hp"]), 7, "the transformed member keeps his current HP (%d/%d): the exchange, the re-install constructor and the refresh write no vitals" % [int(gulu["hp"]), int(gulu["max_hp"])])
	_assert_eq(ActorSpriteKey.row_key(gulu, panels), "017", "the panel title follows the 017 row (邪獸)")
	level37["battle_outcome"] = BattleOutcome.VICTORY_BOSS
	var carry37 := CampaignCarryRules.capture(level37, campaign["carry_policy"])
	_assert_eq([str(carry37["units"]["gulu"]["actor_id"]), str(carry37["units"]["gulu"]["job_up_target_actor_id"]), (carry37["units"]["gulu"]["job_up_history"] as Array).size()], ["008", "017", 1], "the carry records the battle job-up as actor 008 standing on 017 with one history step")
	var scenario38 := BattleScenario.load_file("res://content/battles/battle_038.json")
	var conditional38 := Conditional.apply(scenario38, carry37)
	_assert_true((conditional38["receipt"]["installed"] as Array).has("gulu") and (conditional38["receipt"]["skipped"] as Array).is_empty(), "level 38 fields the transformed 咕嚕 (matched by actor id 008): %s" % str(conditional38["receipt"]))
	var level38 := BattlePlayLoop.apply_campaign_carry(BattlePlayLoop.create([], "", conditional38["scenario"], 7), carry37)
	_assert_eq(level38["campaign_carry_receipt"]["errors"], [], "the carry applies to level 38 without errors")
	_assert_eq(level38["campaign_carry_receipt"].get("job_up_replayed_unit_ids", []), ["gulu"], "level 38 replays the battle job-up history")
	var carried := _unit(level38, "gulu")
	_assert_eq([str(carried["actor_id"]), str(carried["job_up_target_actor_id"]), int(carried["growth_profile"]["job_code"]), int(carried["weapon_code"]), int(carried["level"]), int(carried["kill_count"]), int(carried["pending_stat_points"])], ["008", "017", 97, 53, 4, 3, 5], "咕嚕 enters level 38 in his 017 form with level, kills and unspent points")
	_assert_eq([int(carried["max_hp"]), int(carried["hp"])], [int(gulu["max_hp"]), int(gulu["max_hp"])], "the replayed form derives the same maximum as the battle refresh and restores vitals")
	_assert_eq(carried["learned_skills"], gulu["learned_skills"], "learned skills survive the replay")
	_assert_eq(ActorSpriteKey.row_key(carried, panels), "017", "the title stays 017 in the next battle")
	_battle_job_up_carry = carry37


var _battle_job_up_carry: Dictionary = {}


## The same carry through the product path: a pending hand-off into level 38 fields the
## transformed 咕嚕 (ConditionalPartyRules in _bootstrap_runtime) and spawns him with the
## shared 017 walk frames and FLY002 footsteps; a hand-off without 咕嚕 leaves the slot out.
func _test_battle_job_up_runtime_handoff() -> void:
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/battle_038.json", "carry": _battle_job_up_carry.duplicate(true), "from_scenario_id": "battle_037_level37"}
	var scene = RuntimeScene.instantiate()
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var receipt: Dictionary = RuntimeReadback.interaction_summary(scene).get("conditional_party", {})
	_assert_eq([str(receipt.get("mode", "")), (receipt.get("installed", []) as Array).has("gulu"), receipt.get("skipped", [])], ["install_if_carried", true, []], "level 38 boots with the carried 咕嚕 fielded: %s" % str(receipt))
	var fielded := _unit(scene.play_loop, "gulu")
	_assert_eq([str(fielded.get("actor_id", "")), str(fielded.get("job_up_target_actor_id", "")), int(fielded.get("growth_profile", {}).get("job_code", 0))], ["008", "017", 97], "the runtime's loop holds 咕嚕 in the 017 form")
	_assert_eq(str(RuntimeReadback.runtime_contract_summary(scene).get("actor_frame_actor_ids", {}).get("gulu", "")), "017", "the node is spawned with the shared 017 walk frames")
	_assert_true(scene.actor_node_for_unit("gulu").get_node("WalkAudio").stream.resource_path.ends_with("shared/actor_audio/fly002.wav"), "his footsteps are 017's FLY002 from the shared job-up audio manifest")
	scene.queue_free()
	await process_frame
	await process_frame
	var without_carry := _battle_job_up_carry.duplicate(true)
	(without_carry["units"] as Dictionary).erase("gulu")
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/battle_038.json", "carry": without_carry, "from_scenario_id": "battle_037_level37"}
	var other = RuntimeScene.instantiate()
	other.startup_mode = "product_opening"
	root.add_child(other)
	await process_frame
	await process_frame
	_assert_eq(RuntimeReadback.interaction_summary(other).get("conditional_party", {}).get("skipped", []), ["gulu"], "a party without 咕嚕 enters level 38 without the slot")
	_assert_true(_unit(other.play_loop, "gulu").is_empty() and not _unit(other.play_loop, "claudie").is_empty(), "only the carried conditional member is fielded")
	other.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()


func _test_separate_party_loot_gate() -> void:
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/battle_053.json", "carry": {"schema": CampaignCarryRules.SCHEMA, "units": {}, "loop": {}}, "from_scenario_id": "battle_002_level52"}
	var scene = RuntimeScene.instantiate()
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame
	var progress = scene.campaign_progress
	var controller = scene.settlement_controller
	_assert_true(CampaignProgress.separate_party(progress.campaign, str(scene.scenario_path)), "level 53 is the campaign's separate party")
	var tina := _unit(scene.play_loop, "tina")
	var target := _unit(scene.play_loop, "enemy023_1")
	target["coord"] = tina["coord"] + Vector2i.RIGHT
	target["hp"] = 1
	target["inventory"] = [281, 246, 0, 0, 0, 0, 0, 0] # 281 is a guaranteed important drop
	scene.apply_loop(scene.play_loop, "test")
	var struck: Dictionary = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(scene.play_loop, "attack"), "enemy023_1", func(_n): return 0)
	_assert_true(BattlePlayLoop.loot_waiting(struck) and not struck["settlement"]["pending"].is_empty(), "the kill leaves items in the pool")
	# 稍後 in the get-item window, then the escape victory: the pool is still pending at the result page.
	var deferred: Dictionary = BattlePlayLoop.finish_rewards(struck, struck["settlement"]["sequence"], struck["settlement"]["revision"], false, true)
	deferred["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	var view = scene.get_node("BattlePresentation")
	view._shown_combat_sequence = int(deferred["last_combat"]["sequence"])
	view.aftermath.sequence = view._shown_combat_sequence
	scene.apply_loop(deferred, "test")
	var frames := 0
	while not view.battle_finished and frames < 200:
		if view.dialogue_active(): view.advance_dialogue()
		await process_frame
		frames += 1
	await process_frame
	_assert_true(view.battle_finished, "the separate party's victory reaches the finished-battle state")
	_assert_true(progress.separate_loot_blocking() and not progress.deferred_rewards_ready(), "a separate party's pending pool blocks the hand-off and is not carriable")
	var pending_before: Array = scene.play_loop["settlement"]["pending"].duplicate(true)
	progress.start_next_battle()
	_assert_true(not CampaignProgress.has_pending() and scene.play_loop["settlement"]["pending"] == pending_before, "the gate still refuses and never drains the pool")
	# The battle end (BattleSceneRuntime._advance_battle_end) holds for the pool: it reopens
	# the get-item window and the notice line says what to do.
	_assert_true(progress.hold_for_loot(), "the battle end holds for the separate party's pool")
	_assert_eq(controller.notice.text, progress.SEPARATE_LOOT_PROMPT, "the notice line says what to do with the pool")
	await process_frame
	_assert_true(controller.panel.visible and BattlePlayLoop.loot_waiting(scene.play_loop), "the battle end reopens the get-item window")
	_assert_true(not view.battle_finished, "the finished state leaves while the window is open")
	# Take the important item into 緼娜's bag, 放棄 whatever else dropped.
	controller.panel.rows[0].pressed.emit()
	controller.panel.slots[RuntimeReadback.first_empty_slot(controller.panel)].pressed.emit()
	await process_frame
	_assert_true(_unit(scene.play_loop, "tina")["inventory"].has(281), "the taken item lands in the separate party member's bag")
	if scene.play_loop["settlement"]["pending"].is_empty():
		controller.panel.finish_button.pressed.emit()
	else:
		controller.panel.drop_button.pressed.emit()
		controller.panel.drop_button.pressed.emit() # 再按一次 confirms the abandon
	frames = 0
	while not view.battle_finished and frames < 60:
		await process_frame
		frames += 1
	_assert_true(scene.play_loop["settlement"]["pending"].is_empty() and bool(scene.play_loop["settlement"]["closed"]), "take / 放棄 empties and closes the pool")
	_assert_true(view.battle_finished and not progress.hold_for_loot(), "the battle end no longer holds once the pool is empty")
	_assert_eq(str(CampaignProgress.next_destination(progress.campaign, scene.play_loop, str(scene.scenario_path)).get("title", "")), "歐姆村", "level 53 hands off to 歐姆村")
	progress.start_next_battle()
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/ohm_village_battle.json", "the hand-off works once the pool is settled")
	_assert_true(not (CampaignProgress.pending.get("carry", {}) as Dictionary).has("pending_rewards"), "the separate party's pass-through carry holds no reward pool")
	scene.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.reset_campaign()


## A new launch (empty statics) of the first battle with a persisted position
## further along pauses under the resume prompt; declining clears the save and
## resumes the opening, accepting re-enters the saved scenario with the carry.
func _test_saved_progress() -> void:
	CampaignProgress.reset_campaign()
	var carry := {"schema": "hsl_campaign_carry.v1", "units": {"leonard": {"actor_id": "001", "level": 3, "exp": 0, "pending_stat_points": 0, "equipment": [], "weapon_code": 0, "inventory": [], "kill_count": 4, "attributes": {"str": 9, "dex": 8, "mind": 6, "con": 8}}}, "loop": {"gold": 120}}
	var saved := {"schema": CampaignProgress.SCHEMA, "scenario_path": "res://content/battles/story_058.json", "carry": carry, "from_scenario_id": "battle_002_level52"}
	_assert_true(CampaignProgress.save_progress(saved), "campaign progress can be written")
	_assert_eq(str(CampaignProgress.load_progress().get("scenario_path", "")), "res://content/battles/story_058.json", "campaign progress round-trips")
	CampaignProgress.resume_prompt_in_headless = true
	var scene = RuntimeScene.instantiate()
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	var summary: Dictionary = scene.campaign_progress.summary()
	_assert_true(bool(summary.get("resume_prompt_visible", false)), "first-battle launch offers to resume the saved campaign")
	_assert_true(paused, "the opening pauses under the resume prompt")
	_assert_eq(scene.campaign_progress.resume_button.text, "繼續 · 沃斯菲塔王座廳", "resume button names the saved scenario")
	scene.campaign_progress.decline_saved_progress()
	await process_frame
	_assert_true(not paused, "declining resumes the first battle")
	_assert_true(CampaignProgress.load_progress().is_empty(), "declining forgets the saved position")
	_assert_true(not bool(scene.campaign_progress.summary().get("resume_prompt_visible", true)), "prompt closes after declining")
	scene.queue_free()
	await process_frame
	await process_frame

	CampaignProgress.save_progress(saved)
	var again = RuntimeScene.instantiate()
	again.startup_mode = "product_opening"
	root.add_child(again)
	await process_frame
	await process_frame
	_assert_true(bool(again.campaign_progress.summary().get("resume_prompt_visible", false)), "prompt shows again while the save exists")
	again.campaign_progress.resume_saved_progress(saved)
	await process_frame
	_assert_true(not paused, "accepting unpauses before the reload")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_058.json", "accepting stores the saved scenario as the pending hand-off")
	again.queue_free()
	await process_frame
	await process_frame
	var resumed = RuntimeScene.instantiate()
	resumed.startup_mode = "product_opening"
	root.add_child(resumed)
	await process_frame
	await process_frame
	_assert_eq(resumed.scenario_path, "res://content/battles/story_058.json", "the next runtime enters the saved scenario")
	_assert_true(resumed.opening_coordinator != null and resumed.opening_coordinator.story_mode, "saved story scene resumes through the coordinator")
	_assert_eq((resumed.campaign_handoff.get("carry", {}) as Dictionary).get("loop", {}).get("gold", 0), 120, "the saved carry travels with the resumed scenario")
	_assert_true(not bool(resumed.campaign_progress.summary().get("resume_prompt_visible", true)), "no prompt inside a resumed scenario")
	resumed.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.resume_prompt_in_headless = false
	CampaignProgress.reset_campaign()
