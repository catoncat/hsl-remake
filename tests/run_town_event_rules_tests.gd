extends "res://tests/support/TestSuite.gd"

## Pure-dictionary coverage for TownEventRules, the TOWNDEF te interpreter:
## initial town state from the tracked towndef / provisional initial trees, the
## shared hsl_world_state.v1 literal built here from world_map.json, 歐姆村 /
## 米蘭多 / 席達鎮 / 薛維斯港 / 命運神殿 / 瑪哈亞鎮 chains (dialogue, gold, shop,
## sub-menu, select, money check, item jump, job-up fail branch, menu move-out),
## script act* town actions from winfail001 / winfail021, unknown tokens and
## error paths. No UI, no PlayLoop; nothing here is an original-equivalence claim.

const Rules = preload("res://game/sim/TownEventRules.gd")

const TOWNDEF_PATH := "res://content/imported/hsl/global/world_map/towndef.json"
const WORLD_MAP_PATH := "res://content/imported/hsl/global/world_map/world_map.json"
const TREES_PATH := "res://content/world/town_initial_trees.json"

var towndef: Dictionary = {}
var world_map: Dictionary = {}
var trees: Dictionary = {}


func _init() -> void:
	tag = "TOWN_EVENT_RULES_TESTS"
	report_checks = false


func run() -> void:
	towndef = Rules.load_towndef(TOWNDEF_PATH)
	world_map = Rules.load_world_map(WORLD_MAP_PATH)
	trees = Rules.load_initial_trees(TREES_PATH)
	_assert_true(not towndef.has("error"), "towndef loads: %s" % str(towndef.get("error", "")))
	_assert_true(not world_map.has("error"), "world_map loads: %s" % str(world_map.get("error", "")))
	_assert_true(not trees.has("error"), "initial trees load: %s" % str(trees.get("error", "")))
	if failures.is_empty():
		_initial_state()
		_dialogue_and_gold()
		_shop()
		_sub_menu_and_tree_change()
		_select_branch()
		_check_money()
		_secret_man_purchase()
		_populating_event_30()
		_item_jump_and_over_score()
		_job_up_fail_branch()
		_menu_move_out()
		_script_actions()
		_unknown_token_and_errors()
		_corpus_smoke()


## ---------------------------------------------------------------------------
## Fixtures

func _state() -> Dictionary:
	## hsl_world_state.v1 literal; point/track flags filled from world_map.json.
	var point_flags := {}
	for point in world_map.get("points", []):
		point_flags[str(int(point["id"]))] = (point["flag_names"] as Array).duplicate()
	var track_flags := {}
	for track in world_map.get("tracks", []):
		track_flags[str(int(track["id"]))] = (track["field1_flag_names"] as Array).duplicate()
	return {
		"schema": "hsl_world_state.v1",
		"current_point": 1,
		"point_flags": point_flags,
		"track_flags": track_flags,
		"point_events": {},
		"encounter_ratios": {},
		"point_modes": {},
		"track_modes": {},
		"show_track_points": [],
		"towns": Rules.initial_town_state(towndef, trees),
		"over_score": {},
		"visited_points": [1],
		# Deterministic tavern secret-man die (the original rolls rand(100)+1; strict < ratio, default 8).
		"secret_roll": 100,
	}


func _party(gold: int = 0, items: Array = [], members: Array = ["SID_雷歐納德", "SID_琥"]) -> Dictionary:
	return {"gold": gold, "items": items, "members": members}


func _kinds(effects: Array) -> Array:
	var kinds: Array = []
	for effect in effects:
		kinds.append(str((effect as Dictionary).get("kind", "")))
	return kinds


func _effects_of(run: Dictionary, kind: String) -> Array:
	var result: Array = []
	for effect in run.get("effects", []):
		if str((effect as Dictionary).get("kind", "")) == kind:
			result.append(effect)
	return result


func _message_ids(effects: Array) -> Array:
	var ids: Array = []
	for effect in effects:
		var kind := str((effect as Dictionary).get("kind", ""))
		if kind == "shape_message" or kind == "player_message":
			ids.append(int((effect as Dictionary).get("message_id", 0)))
	return ids


## ---------------------------------------------------------------------------

func _initial_state() -> void:
	var state := _state()
	_assert_eq((state["point_flags"] as Dictionary).size(), 45, "45 points")
	_assert_eq((state["track_flags"] as Dictionary).size(), 44, "44 tracks")
	var hidden := 0
	for key in (state["track_flags"] as Dictionary).keys():
		if (state["track_flags"][key] as Array).has("bmpmHidden"):
			hidden += 1
	_assert_eq(hidden, 18, "18 hidden tracks")
	var towns: Dictionary = state["towns"]
	_assert_eq(towns.size(), 12, "12 towns")
	_assert_true(towns.has("1") and towns.has("16") and towns.has("42"), "town ids are string point ids")
	_assert_eq(towns["1"]["tree"], {"0": [1, 2, 3]}, "歐姆村 initial root")
	_assert_eq(towns["4"]["tree"], {"0": [4, 5, 6, 7], "7": [8, 12, 13, 14]}, "米蘭多 initial tree")
	_assert_eq(towns["6"]["tree"], {"0": [16, 17, 18, 20], "20": [21, 22, 23]}, "席達鎮 initial tree")
	_assert_eq(towns["11"]["tree"], {"0": []}, "薛維斯港 starts empty (script-populated)")
	_assert_eq(int(towns["1"]["exec_event"]), 0, "exec_event starts 0")
	_assert_eq(towns["1"]["secret_man"], null, "secret_man starts null")
	var entries := Rules.menu_entries(state, towndef, 1)
	var labels: Array = []
	for entry in entries:
		labels.append([int(entry["code"]), str(entry["show_name_text"]), int(entry["item_code"])])
	_assert_eq(labels, [[1, "武器店", 1], [2, "護甲店", 2], [3, "道具店", 3]], "歐姆村 menu entries")
	_assert_eq(Rules.menu_entries(state, towndef, 4, 7).size(), 4, "米蘭多酒館 sub-menu entries")
	_assert_true(bool(Rules.menu_entries(state, towndef, 4)[3]["sub_menu"]), "酒館 flagged as sub-menu")
	_assert_eq(Rules.initial_town_state({"schema": "x"}, trees), {"error": "towndef_schema_mismatch"}, "initial_town_state rejects bad towndef")


func _dialogue_and_gold() -> void:
	var state := _state()
	var party := _party(100)
	var run := Rules.begin_event(state, party, towndef, 1, 9)
	_assert_true(not run.has("error"), "event 9 begins: %s" % str(run.get("error", "")))
	_assert_eq(_kinds(run["effects"]), ["shape_message", "player_message", "shape_message", "player_message"], "event 9: two exchanges")
	_assert_eq(_message_ids(run["effects"]), [858, 859, 860, 861], "event 9 message ids")
	_assert_eq((run["effects"][0] as Dictionary)["face_member"], "SHAPE\\FACE0062.SHP", "shape face member")
	_assert_eq(int((run["effects"][0] as Dictionary)["name_resource_id"]), 656, "shape name id")
	_assert_eq(str((run["effects"][1] as Dictionary)["player_token"]), "SID_雷歐納德", "player token")
	_assert_eq(int((run["effects"][1] as Dictionary)["player_id"]), 0, "player id resolved via extras.h")
	_assert_true(bool(run["done"]) and run["pending"] == null, "event 9 completes")
	_assert_eq(int(party["gold"]), 100, "input party untouched")
	_assert_eq(int(state["towns"]["1"]["exec_event"]), 0, "input state untouched")

	var run10 := Rules.begin_event(state, party, towndef, 1, 10)
	_assert_eq(_kinds(run10["effects"]), ["shape_message", "player_message", "shape_message", "get_gold", "player_message", "set_exec_event"], "event 10 effects")
	_assert_eq(_effects_of(run10, "get_gold")[0], {"kind": "get_gold", "amount": 2000, "display": false}, "get_gold 2000")
	_assert_eq(int(run10["party"]["gold"]), 2100, "gold added")
	_assert_eq(_effects_of(run10, "set_exec_event")[0], {"kind": "set_exec_event", "town_id": 1, "event": 11}, "set_exec_event 11")
	_assert_eq(int(run10["state"]["towns"]["1"]["exec_event"]), 11, "exec_event written")
	_assert_true(bool(run10["done"]), "event 10 completes")
	var run11 := Rules.begin_event(run10["state"], run10["party"], towndef, 1, int(run10["state"]["towns"]["1"]["exec_event"]))
	_assert_eq(int(run11["state"]["towns"]["1"]["exec_event"]), 0, "event 11 clears exec_event")


func _shop() -> void:
	var run := Rules.begin_event(_state(), _party(), towndef, 1, 1)
	_assert_eq(_kinds(run["effects"]), ["shape_message"], "event 1: greeting before shop")
	_assert_eq(run["pending"], {"kind": "shop", "shop_name_id": 32, "item_code": 1, "item_ids": [1, 81, 101], "event": 1}, "shop pending with 歐姆村 goods")
	_assert_true(not bool(run["done"]), "shop keeps the run open")
	var closed := Rules.resume(run)
	_assert_true(bool(closed["done"]) and closed["pending"] == null, "shop closed completes event 1")
	var run4 := Rules.begin_event(_state(), _party(), towndef, 4, 4)
	var after := Rules.resume(run4)
	_assert_eq(_message_ids(after["effects"]), [867, 868], "米蘭多武器店 farewell after the shop")


func _sub_menu_and_tree_change() -> void:
	var run := Rules.begin_event(_state(), _party(), towndef, 4, 7)
	_assert_eq(_kinds(run["effects"]), ["shape_message", "secret_man"], "tavern greeting then the secret-man roll")
	_assert_eq(_effects_of(run, "secret_man")[0], {"kind": "secret_man", "action": "absent", "town_id": 4, "tavern_event": 7, "roll": 100, "ratio": 8}, "a roll of 100 against the default ratio 8 keeps the secret man away")
	_assert_eq(run["state"]["towns"]["4"]["secret_man"], {"cache": -1, "tavern_event": 7, "roll": 100, "ratio": 8, "forced": false}, "a failed roll is cached as -1")
	var pending: Dictionary = run["pending"]
	_assert_eq(str(pending.get("kind", "")), "sub_menu", "sub-menu pending")
	_assert_eq(pending.get("children"), [8, 12, 13, 14], "tavern children from the initial tree")
	var texts: Array = []
	for entry in pending.get("entries", []):
		texts.append(str(entry["show_name_text"]))
	_assert_eq(texts, ["酒館老闆", "侍女", "獸人", "旅行者"], "tavern entry labels")
	var picked := Rules.resume(run, {"event": 14})
	var new_effects: Array = (picked["effects"] as Array).slice((run["effects"] as Array).size())
	_assert_eq(_message_ids(new_effects).size(), 13, "旅行者 dialogue length")
	_assert_eq(_effects_of(picked, "tree_change"), [
		{"kind": "tree_change", "town_id": 4, "parent": 7, "added": [], "removed": [14]},
		{"kind": "tree_change", "town_id": 4, "parent": 7, "added": [15], "removed": []},
	], "teDeleteSelfTE,7,1,14 / teAddSelfTE,7,1,15")
	_assert_eq(picked["state"]["towns"]["4"]["tree"]["7"], [8, 12, 13, 15], "tree after swap")
	_assert_eq(str((picked["pending"] as Dictionary).get("kind", "")), "sub_menu", "menu re-opens after the child")
	_assert_eq((picked["pending"] as Dictionary).get("children"), [8, 12, 13, 15], "re-opened menu lists the new child")
	var again := Rules.resume(picked, {"event": 15})
	_assert_eq(_message_ids((again["effects"] as Array).slice((picked["effects"] as Array).size())), [884], "旅行者二 single line")
	var left := Rules.resume(again, {"exit": true})
	_assert_true(bool(left["done"]) and left["pending"] == null, "exit closes the tavern")
	_assert_eq((left["effects"] as Array).back(), {"kind": "secret_man", "action": "delete", "town_id": 4}, "teDeleteSecretMan after the menu")
	_assert_eq(left["state"]["towns"]["4"]["secret_man"], null, "secret man cleared")
	_secret_man_roll()


func _secret_man_roll() -> void:
	## Static-derived mechanism (0x454db0): strict rand(100)+1 < ratio adds the table
	## event under the tavern and caches it; mode 1 forces; teDeleteSecretMan removes him.
	var state := _state()
	state["secret_roll"] = 7
	var run := Rules.begin_event(state, _party(), towndef, 4, 7)
	_assert_eq(_effects_of(run, "secret_man")[0], {"kind": "secret_man", "action": "appear", "town_id": 4, "tavern_event": 7, "event": 123, "roll": 7, "ratio": 8, "forced": false}, "a roll of 7 < 8 brings the first table secret man (123)")
	_assert_eq((run["pending"] as Dictionary).get("children"), [8, 12, 13, 14, 123], "the tavern menu lists him")
	var labels: Array = []
	for entry in (run["pending"] as Dictionary).get("entries", []):
		labels.append(str(entry["show_name_text"]))
	_assert_eq(labels.back(), "神秘男子", "he is shown as 神秘男子")
	var left := Rules.resume(run, {"exit": true})
	_assert_eq(left["state"]["towns"]["4"]["tree"]["7"], [8, 12, 13, 14], "teDeleteSecretMan removes him from the tavern again")
	_assert_eq(left["state"]["towns"]["4"]["secret_man"], null, "and clears the cache")
	state["secret_roll"] = 8
	var equal := Rules.begin_event(state, _party(), towndef, 4, 7)
	_assert_eq(str((_effects_of(equal, "secret_man")[0] as Dictionary).get("action", "")), "absent", "a roll equal to the ratio fails (strict comparison)")
	var cached_state: Dictionary = (equal["state"] as Dictionary).duplicate(true)
	cached_state["secret_roll"] = 1
	var cached := Rules.begin_event(cached_state, _party(), towndef, 4, 7)
	_assert_eq(str((_effects_of(cached, "secret_man")[0] as Dictionary).get("action", "")), "cached", "a -1 cache is not re-rolled while it stands")
	var forced := Rules.apply_script_town_actions(cached_state, [{"name": "actAppearSecretMan", "args": ["town_米蘭多", "7", "1"]}], towndef)
	_assert_eq((((forced["state"]["towns"] as Dictionary)["4"] as Dictionary)["tree"] as Dictionary)["7"], [8, 12, 13, 14, 123], "mode 1 forces him in despite the cache")


func _select_branch() -> void:
	var run := Rules.begin_event(_state(), _party(), towndef, 6, 106)
	_assert_eq(_kinds(run["effects"]), ["shape_message", "delay"], "妖精三 leads into the choice")
	var pending: Dictionary = run["pending"]
	_assert_eq(pending.get("kind"), "select", "select pending")
	_assert_eq(pending.get("speaker"), "SID_雷歐納德", "select speaker")
	_assert_eq(pending.get("options"), [{"message_id": 1197, "event": 111}, {"message_id": 1198, "event": 112}], "select options")
	var second := Rules.resume(run, {"index": 1})
	_assert_eq(_message_ids((second["effects"] as Array).slice(2)), [1200], "branch two runs event 112")
	_assert_true(bool(second["done"]), "branch completes the run")
	var first := Rules.resume(run, 0)
	_assert_eq(_message_ids((first["effects"] as Array).slice(2)), [1199], "branch one runs event 111")
	var bad := Rules.resume(run, {"index": 7})
	_assert_true(bool(bad["done"]), "invalid choice does not hang")
	_assert_eq(str((bad["records"] as Array).back()["status"]), "invalid_choice", "records note the invalid choice")


func _check_money() -> void:
	var state := _state()
	var poor := Rules.begin_event(state, _party(100), towndef, 11, 51)
	_assert_eq(_kinds(poor["effects"]), ["shape_message", "check_failed"], "insufficient gold: message, no deduction, the event ends (0x4555a5)")
	_assert_eq((poor["effects"][0] as Dictionary)["message_id"], 1282, "抱歉, 您的金錢不足")
	_assert_eq((poor["effects"][1] as Dictionary), {"kind": "check_failed", "token": "teCheckMoney", "needed": 500, "have": 100}, "check_failed payload")
	_assert_true(bool(poor["done"]), "aborted run is done")
	_assert_eq(int(poor["party"]["gold"]), 100, "no gold spent")
	_assert_eq(poor["next_level_event"], [], "no level hand-off")
	var rich := Rules.begin_event(state, _party(600), towndef, 11, 51)
	_assert_eq(_kinds(rich["effects"]), ["spend_gold", "shape_message", "delay", "bm_flag_change", "bm_point_mode", "next_level"], "ship fare path")
	_assert_eq(int(rich["party"]["gold"]), 100, "fare spent")
	_assert_eq(_effects_of(rich, "bm_flag_change")[0], {"kind": "bm_flag_change", "target": "point", "id": 16, "flag": "bmpmHidden", "set": false}, "town_命運神殿 resolves to point 16")
	_assert_eq(rich["state"]["point_modes"], {"16": 2}, "gameBMShow = 2")
	_assert_eq(rich["next_level_event"], [16, 49], "teSetNextPlayLevelEvent town_命運神殿,gameBigMapLevel")
	_assert_true(bool(rich["done"]), "leaving town ends the run")


func _secret_man_purchase() -> void:
	## teSecretManBuyThing (0x454e20 case 0x27, static-derived): the 神秘男子's gift
	## costs secret_man_goods[secret_man_index].price (5000 first), grants one item of
	## that row (positional rand over its 15 slots) the teGetItem way, and advances the
	## counter; short of gold → face-less fail message 1282 and jump to the fail event 122.
	var state := _state()
	state["secret_pick"] = 1
	var bought := Rules.begin_event(state, _party(5200), towndef, 4, 121)
	_assert_eq(_kinds(bought["effects"]), ["shape_message", "spend_gold", "get_item", "secret_man", "shape_message", "secret_man"], "pitch 1620, purchase, farewell 1622, teDeleteSecretMan")
	_assert_eq(_message_ids(bought["effects"]), [1620, 1622], "NICE！有眼光 … 下次有緣再相見")
	_assert_eq(_effects_of(bought, "spend_gold")[0], {"kind": "spend_gold", "amount": 5000}, "row 0 costs 5000 (pitch 1608 quotes $5000)")
	_assert_eq(_effects_of(bought, "get_item")[0], {"kind": "get_item", "item_id": 145, "count": 1}, "slot 1 of row 0 is 145 怨念血衣")
	_assert_eq(_effects_of(bought, "secret_man")[0], {"kind": "secret_man", "action": "purchase", "index": 0, "price": 5000, "item_id": 145, "pick": 1, "next_index": 1}, "purchase receipt")
	_assert_eq(int(bought["party"]["gold"]), 200, "gold deducted at once")
	_assert_eq(bought["party"]["items"], [{"id": 145, "count": 1}], "the gift joins the party items")
	_assert_eq(int(bought["state"]["secret_man_index"]), 1, "counter advanced: the next pitch is event 113 / $7500")
	_assert_true(bool(bought["done"]), "event 121 completes")
	var again_state: Dictionary = (bought["state"] as Dictionary).duplicate(true)
	again_state["secret_pick"] = 0
	var second := Rules.begin_event(again_state, _party(7500), towndef, 4, 121)
	_assert_eq(_effects_of(second, "spend_gold")[0], {"kind": "spend_gold", "amount": 7500}, "row 1 costs 7500")
	_assert_eq(_effects_of(second, "get_item")[0], {"kind": "get_item", "item_id": 9, "count": 1}, "slot 0 of row 1 is 9")
	var poor := Rules.begin_event(again_state, _party(7499), towndef, 4, 121)
	_assert_eq(_kinds(poor["effects"]), ["shape_message", "shape_message", "check_failed", "shape_message", "secret_man"], "pitch, fail message, then the fail event 122 (OH NO … + teDeleteSecretMan)")
	_assert_eq(_message_ids(poor["effects"]), [1620, 1282, 1623], "1282 抱歉, 您的金錢不足！ then 1623")
	_assert_eq(str((poor["effects"][1] as Dictionary).get("face_member", "x")), "", "[shape] -1 means no face")
	_assert_eq(int((poor["effects"][1] as Dictionary).get("name_resource_id", 0)), 1607, "spoken as 神秘男子")
	_assert_eq(int(poor["party"]["gold"]), 7499, "nothing deducted")
	_assert_eq(int(poor["state"]["secret_man_index"]), 1, "counter unchanged")
	var capped_state: Dictionary = _state()
	capped_state["secret_man_index"] = 8
	capped_state["secret_pick"] = 14
	var last := Rules.begin_event(capped_state, _party(99999), towndef, 4, 121)
	_assert_eq(_effects_of(last, "spend_gold")[0], {"kind": "spend_gold", "amount": 99999}, "row 8 costs 99999")
	_assert_eq(_effects_of(last, "get_item")[0], {"kind": "get_item", "item_id": 301, "count": 1}, "slot 14 of row 8 is 301 透明天晶")
	_assert_eq(int(last["state"]["secret_man_index"]), 8, "the counter stops at 8")


func _populating_event_30() -> void:
	var run := Rules.begin_event(_state(), _party(), towndef, 6, 30)
	_assert_true(bool(run["done"]), "event 30 completes")
	var towns: Dictionary = run["state"]["towns"]
	_assert_eq(towns["11"]["tree"], {"0": [33, 34, 35, 36, 41], "36": [37, 38, 39], "41": [42, 43, 44]}, "薛維斯港 populated by teAddTE")
	_assert_eq(int(towns["11"]["exec_event"]), 32, "薛維斯港 exec_event 32")
	_assert_eq(int(towns["6"]["exec_event"]), 0, "席達鎮 exec_event cleared")
	_assert_eq(run["state"]["track_flags"]["10"], [], "track 10 unhidden")
	_assert_eq(run["state"]["point_flags"]["11"], ["bmpmTown"], "point 11 keeps bmpmTown")
	_assert_eq(run["state"]["show_track_points"], [9], "teBMSetShowTrackPoint town_曼多力亞")
	_assert_eq(run["state"]["point_events"], {"9": {"event": 900, "flag": "bmpmGeneral"}}, "teBMSetPointEvent town_曼多力亞,900,bmpmGeneral")
	_assert_eq(towns["6"]["tree"]["20"], [21, 22, 23], "removing an absent child is a no-op")
	var followup := Rules.begin_event(run["state"], _party(), towndef, 11, int(towns["11"]["exec_event"]))
	_assert_eq(followup["state"]["towns"]["16"]["tree"], {"0": [55, 54, 72], "55": [56, 57, 58, 59], "72": [73]}, "命運神殿 populated by event 32")
	_assert_eq(int(followup["state"]["towns"]["16"]["exec_event"]), 53, "命運神殿 exec_event 53")


func _item_jump_and_over_score() -> void:
	var state := _state()
	var with_item := Rules.begin_event(state, _party(0, [{"id": 203, "count": 1}]), towndef, 6, 108)
	_assert_eq(_effects_of(with_item, "remove_item"), [{"kind": "remove_item", "item_id": 203, "count": 1}], "item 203 consumed")
	_assert_eq(with_item["party"]["items"], [], "item removed from party")
	_assert_eq(with_item["state"]["over_score"], {"3": 2, "2": 0}, "event 191 then 109 over scores")
	_assert_eq(with_item["state"]["towns"]["6"]["tree"]["20"], [21, 22, 23, 110], "event 109 adds 110 under the tavern")
	_assert_eq(with_item["state"]["towns"]["23"]["tree"], {"0": [92], "92": [102]}, "teAddTE ensures 瑪哈亞鎮酒館 then adds 102")
	_assert_true(bool(with_item["done"]), "chain completes")
	var without := Rules.begin_event(state, _party(), towndef, 6, 108)
	_assert_eq(_message_ids(without["effects"]), [2569], "no item: fall through to the message")
	_assert_eq(without["state"]["over_score"], {}, "no score without the item")


func _job_up_fail_branch() -> void:
	var run := Rules.begin_event(_state(), _party(), towndef, 16, 61)
	_assert_eq(_kinds(run["effects"]), ["player_message", "player_message", "check_failed"], "job-up without member records: line, fail message, check receipt")
	_assert_eq((run["effects"][2] as Dictionary)["token"], "teCheckJobUp", "failed token name")
	_assert_eq((run["effects"][2] as Dictionary)["reason"], "member_not_in_party", "no member record → fail branch")
	_assert_eq((run["effects"][1] as Dictionary)["message_id"], 1298, "fail message 1298")
	var pending: Dictionary = run["pending"]
	_assert_eq(pending.get("kind"), "player_select", "fail event 71 offers the player select")
	_assert_eq((pending.get("options") as Array).size(), 8, "eight candidates")
	_assert_eq((pending.get("options") as Array)[0], {"player_token": "SID_雷歐納德", "player_id": 0, "event": 61, "in_party": true}, "first option")
	_assert_eq(bool((pending.get("options") as Array)[1]["in_party"]), false, "緹娜 not in the fixture party")
	var found := false
	for record in run["records"]:
		if str((record as Dictionary).get("token", "")) == "teCheckJobUp":
			found = str((record as Dictionary).get("status", "")) == "fail_branch" and (record as Dictionary).has("provisional")
	_assert_true(found, "records carry the job-up reading")
	_job_up_success_and_chain()


func _job_up_success_and_chain() -> void:
	## 0x434770: str/dex/mind/con >= job cap - 50 (SwordMan 90/88/80/94 → 40/38/30/44).
	var member := {"unit_id": "leonard", "actor_id": "001", "attributes": {"str": 40, "dex": 38, "mind": 30, "con": 44}}
	var party := _party(0, [], ["SID_雷歐納德", "SID_琥"])
	party["member_records"] = {"SID_雷歐納德": member.duplicate(true)}
	var run := Rules.begin_event(_state(), party, towndef, 16, 61)
	_assert_eq(_kinds(run["effects"]), ["player_message", "job_up", "delay", "player_message"], "job-up success: line, exchange, delay, success line")
	var effect: Dictionary = run["effects"][1]
	_assert_eq([effect["from_actor_id"], effect["to_actor_id"], int(effect["job_code"]), int(effect["flag"])], ["001", "010", 81, 0x80000000], "雷歐納德 001 → 010 劍豪 with the first-tier flag")
	_assert_eq((run["effects"][3] as Dictionary)["message_id"], 1301, "success line 1301")
	_assert_eq(str((run["pending"] as Dictionary).get("kind", "")), "player_select", "teExecEvent 71 re-opens the ritual select")
	var record: Dictionary = run["party"]["member_records"]["SID_雷歐納德"]
	_assert_eq([record["job_up_target_actor_id"], int(record["job_up_flags"]), (record["job_up_history"] as Array).size()], ["010", 0x80000000, 1], "member record carries the job-up layer")
	_assert_eq((record["job_up_history"] as Array)[0], {"from_actor_id": "001", "to_actor_id": "010", "flag": 0x80000000, "from_job_code": 80, "job_code": 81}, "history step records both jobs")
	# One attribute below the margin → the original fail branch (1298 → 71).
	var weak := member.duplicate(true)
	weak["attributes"]["con"] = 43
	party["member_records"] = {"SID_雷歐納德": weak}
	var failed := Rules.begin_event(_state(), party, towndef, 16, 61)
	_assert_eq(_kinds(failed["effects"]), ["player_message", "player_message", "check_failed"], "below cap-50 → fail branch")
	_assert_eq((failed["effects"][2] as Dictionary)["reason"], "attribute_below_cap_margin_con", "the failing attribute is named")
	_assert_eq((failed["effects"][2] as Dictionary)["checks"]["con"], {"value": 43, "needed": 44}, "check receipt")
	_assert_eq(str((failed["pending"] as Dictionary).get("kind", "")), "player_select", "fail event 71")
	# Chain end: 琥 on 012 (job_up_code 0) can never pass again.
	var hu := {"unit_id": "hu", "actor_id": "003", "attributes": {"str": 999, "dex": 999, "mind": 999, "con": 999}, "job_up_target_actor_id": "012", "job_up_flags": 0x80000000, "job_up_history": [{"from_actor_id": "003", "to_actor_id": "012", "flag": 0x80000000, "from_job_code": 83, "job_code": 84}]}
	party["member_records"] = {"SID_琥": hu}
	var ended := Rules.begin_event(_state(), party, towndef, 16, 63)
	_assert_eq((ended["effects"][2] as Dictionary)["reason"], "job_up_code_zero", "012 has job-up code 0")
	# teCheckJobUp2 (event 79): same condition on the current row (010 caps 130/112/100/110), flag 0x40000000, target 019.
	var master := {"unit_id": "leonard", "actor_id": "001", "attributes": {"str": 80, "dex": 62, "mind": 50, "con": 60}, "job_up_target_actor_id": "010", "job_up_flags": 0x80000000, "job_up_history": [{"from_actor_id": "001", "to_actor_id": "010", "flag": 0x80000000, "from_job_code": 80, "job_code": 81}]}
	var tina := {"unit_id": "tina", "actor_id": "002", "attributes": {"str": 1, "dex": 1, "mind": 1, "con": 1}, "job_up_target_actor_id": "020", "job_up_flags": 0xc0000000, "job_up_history": [{"from_actor_id": "002", "to_actor_id": "011", "flag": 0x80000000, "from_job_code": 85, "job_code": 86}, {"from_actor_id": "011", "to_actor_id": "020", "flag": 0x40000000, "from_job_code": 86, "job_code": 87}]}
	party = _party(0, [], ["SID_雷歐納德", "SID_緹娜"])
	party["member_records"] = {"SID_雷歐納德": master, "SID_緹娜": tina}
	var second := Rules.begin_event(_state(), party, towndef, 16, 79)
	var second_effect: Dictionary = _effects_of(second, "job_up")[0]
	_assert_eq([second_effect["from_actor_id"], second_effect["to_actor_id"], int(second_effect["job_code"]), int(second_effect["flag"])], ["010", "019", 82, 0x40000000], "second tier 010 → 019 終焉劍使")
	var second_record: Dictionary = second["party"]["member_records"]["SID_雷歐納德"]
	_assert_eq([second_record["job_up_target_actor_id"], int(second_record["job_up_flags"]), (second_record["job_up_history"] as Array).size()], ["019", 0xc0000000, 2], "both flags and a two-step history")
	_assert_true(_kinds(second["effects"]).has("job_up_town_writes"), "0x434680: both second titles held → 兩棲族部落 writes")
	var amphibian: Dictionary = second["state"]["towns"]["14"]
	_assert_eq(int(amphibian["exec_event"]), 153, "兩棲族部落 exec event 153")
	_assert_eq(amphibian["tree"]["145"], [147, 150, 151], "集會場 children 147/150/151")
	for shop in [142, 143, 144]:
		_assert_true(not (amphibian["tree"]["0"] as Array).has(shop), "shop %d removed" % shop)
	for closed in [154, 155, 156]:
		_assert_true((amphibian["tree"]["0"] as Array).has(closed), "closed-shop entry %d added" % closed)
	# Up2 before any first-tier title: the original has no separate check, so it succeeds onto 010 with the second-tier flag.
	party["member_records"] = {"SID_雷歐納德": member.duplicate(true), "SID_緹娜": tina}
	var early := Rules.begin_event(_state(), party, towndef, 16, 79)
	var early_effect: Dictionary = _effects_of(early, "job_up")[0]
	_assert_eq([early_effect["to_actor_id"], int(early_effect["flag"])], ["010", 0x40000000], "teCheckJobUp2 without a first title still merges 010 (flag differs only)")
	_assert_true(not _kinds(early["effects"]).has("job_up_town_writes"), "no 兩棲族部落 writes while 雷歐納德 can still job up")


func _menu_move_out() -> void:
	var populated := Rules.apply_script_town_actions(_state(), [
		{"name": "actAddTE", "args": ["town_瑪哈亞鎮", "89", "0"]},
		{"name": "actAddTE", "args": ["town_瑪哈亞鎮", "92", "5", "93", "94", "95", "96", "97"]},
	], towndef)
	_assert_eq(populated["state"]["towns"]["23"]["tree"], {"0": [89, 92], "92": [93, 94, 95, 96, 97]}, "winfail021 populates 瑪哈亞鎮")
	var run := Rules.begin_event(populated["state"], _party(), towndef, 23, 92)
	_assert_eq(str((run["pending"] as Dictionary).get("kind", "")), "sub_menu", "tavern menu")
	var mystery := Rules.resume(run, {"event": 96})
	_assert_eq(str((mystery["pending"] as Dictionary).get("kind", "")), "select", "神秘男子 chain ends in a select")
	_assert_eq(int(mystery["state"]["towns"]["23"]["secret_appear_ratio"]), 8, "teSetSecretAppearRatio 8")
	_assert_eq(mystery["state"]["towns"]["23"]["tree"]["92"], [93, 94, 95, 97, 123], "96 removes itself and its forced teAppearSecretMan adds table entry 123 to the tavern")
	_assert_true(_kinds(mystery["effects"]).has("menu_move_out"), "menu_move_out effect")
	var declined := Rules.resume(mystery, {"index": 1})
	_assert_true(bool(declined["done"]) and declined["pending"] == null, "teMenuMoveOut skips re-opening the tavern")
	_assert_eq(_effects_of(declined, "secret_man").back(), {"kind": "secret_man", "action": "delete", "town_id": 23}, "tavern tail still runs")


func _script_actions() -> void:
	var result := Rules.apply_script_town_actions(_state(), [
		{"name": "actBMSetPointEvent", "args": ["1", "501", "0"]},
		{"name": "actSetTownExecEvent", "args": ["town_歐姆村", "9"]},
		{"name": "actBMSetPointEncounterRatio", "args": ["2", "20"]},
		{"name": "actBMSetTrackFlag", "args": ["3", "bmpmHidden"]},
		{"name": "actSetBMWalkToPoint", "args": ["30", "31"]},
		{"name": "actSetBMWalkerPlayerID", "args": ["SID_琥"]},
	], towndef)
	_assert_true(not result.has("error"), "script actions apply")
	_assert_eq(int(result["state"]["towns"]["1"]["exec_event"]), 9, "winfail001 actSetTownExecEvent,town_歐姆村,9")
	_assert_eq(result["state"]["point_events"], {"1": {"event": 501, "flag": ""}}, "actBMSetPointEvent,1,501,0")
	_assert_eq(result["state"]["encounter_ratios"], {"2": 20}, "encounter ratio")
	_assert_eq(result["state"]["track_flags"]["3"], ["bmpmHidden"], "track 3 hidden")
	_assert_eq(int(result["state"]["current_point"]), 1, "walk-to leaves current_point to the map runtime")
	_assert_eq(result["state"]["pending_walk"], {"from": 30, "to": 31}, "actSetBMWalkToPoint leaves pending_walk for the map")
	# actBMSetPointEvent with flags 0 changes no type / Visit bit; a typed write replaces the type and clears Visit.
	_assert_eq(result["state"]["point_flags"]["1"], ["bmpmTown"], "flags 0 leaves 歐姆村's type alone")
	var retyped := Rules.apply_script_town_actions(result["state"], [{"name": "actBMSetPointEvent", "args": ["town_曼多力亞", "9", "bmpmBattle"]}, {"name": "actBMSetPointEvent", "args": ["9", "-1", "bmpmTown"]}], towndef)
	_assert_eq(retyped["state"]["point_flags"]["9"], ["bmpmTown"], "STORY008 turns 曼多力亞 into a Battle point, STORY009's -1 keeps the event and restores Town")
	_assert_eq(retyped["state"]["point_events"]["9"], {"event": 9, "flag": "bmpmTown"}, "event -1 keeps the previous event value (0x426c70)")
	_assert_eq(_kinds(result["effects"]), ["bm_point_event", "set_exec_event", "bm_encounter_ratio", "bm_flag_change", "bm_walk_to_point", "recorded_only"], "script effects")
	var entered := Rules.begin_event(result["state"], _party(), towndef, 1, int(result["state"]["towns"]["1"]["exec_event"]))
	_assert_eq(_message_ids(entered["effects"]), [858, 859, 860, 861], "entering 歐姆村 runs event 9")


func _unknown_token_and_errors() -> void:
	var mini := {
		"schema": "hsl_towndef.v1",
		"symbols": {"town_A": 1},
		"items": [],
		"town_events": [
			{"code": 1, "comment": "A", "show_name": {"resource_id": 30, "text": "x"}, "item_code": null, "events": [
				{"token": "teBogusToken", "args": ["1", "2"]},
				{"token": "teCheckMoney2", "args": []},
				{"token": "tePlayerMessage", "args": ["SID_x", "5", "0"]},
			]},
		],
	}
	var state := _state()
	var run := Rules.begin_event(state, _party(), mini, 1, 1)
	_assert_eq(_kinds(run["effects"]), ["recorded_only", "recorded_only", "player_message"], "unknown tokens are recorded, chain continues")
	_assert_eq((run["records"][0] as Dictionary)["status"], "unknown_token", "unknown token status")
	_assert_eq((run["records"][1] as Dictionary)["status"], "recorded_only", "signature-less token status")
	_assert_true(bool(run["done"]), "run completes")
	_assert_eq(Rules.begin_event({"schema": "other"}, _party(), towndef, 1, 9).get("error"), "state_schema_mismatch", "state schema check")
	_assert_eq(Rules.begin_event(state, _party(), towndef, 99, 9).get("error"), "unknown_town:99", "unknown town")
	_assert_eq(Rules.begin_event(state, _party(), towndef, 1, 999).get("error"), "unknown_event:999", "unknown event")
	_assert_eq(Rules.begin_event(state, _party(), {"schema": "x"}, 1, 9).get("error"), "towndef_schema_mismatch", "towndef schema check")
	_assert_eq(Rules.load_towndef("res://content/does_not_exist.json").get("error"), "missing_file", "missing file")
	_assert_eq(Rules.load_towndef(WORLD_MAP_PATH).get("error"), "schema_mismatch", "wrong schema file")
	var done := Rules.begin_event(state, _party(), towndef, 1, 9)
	var again := Rules.resume(done, null)
	_assert_eq((again["records"] as Array).back()["status"], "ignored_after_done", "resume after done is a no-op")


func _corpus_smoke() -> void:
	## Every TOWNDEF.H token is either executed or explicitly recorded-only, and
	## all 191 events run to completion (pendings auto-driven) without unknown
	## tokens, errors or step-limit hits. Robustness only, not semantics.
	for token in (towndef["token_ids"] as Dictionary).keys():
		_assert_true(Rules.SUPPORTED_TOKENS.has(token) or Rules.RECORDED_ONLY_TOKENS.has(token), "token classified: %s" % str(token))
	var state := _state()
	var party := _party(100000, [], ["SID_雷歐納德", "SID_緹娜", "SID_琥", "SID_漢克斯", "SID_雪拉", "SID_雷特", "SID_嚎", "SID_克羅蒂"])
	var unknown := 0
	var completed := 0
	var cycles: Array = []
	for record in towndef["town_events"]:
		var code := int((record as Dictionary)["code"])
		var run := Rules.begin_event(state, party, towndef, 1, code)
		var seen: Array = []
		var cycled := false
		while not bool(run["done"]) and not cycled:
			var pending: Dictionary = run["pending"]
			var key := "%s/%d" % [str(pending.get("kind", "")), int(pending.get("event", 0))]
			if seen.has(key):
				cycled = true  # data loop (命運神殿 ritual: job-up always fails in this reading)
				break
			seen.append(key)
			_assert_true((run["frames"] as Array).size() <= 3, "event %d: stack stays flat (%d)" % [code, (run["frames"] as Array).size()])
			match str(pending.get("kind", "")):
				"select", "player_select":
					run = Rules.resume(run, {"index": 0})
				"sub_menu":
					run = Rules.resume(run, {"exit": true})
				_:
					run = Rules.resume(run)
		_assert_true((bool(run["done"]) or cycled) and not run.has("error"), "event %d completes or cycles: %s" % [code, str(run.get("error", "pending"))])
		if bool(run["done"]) and not run.has("error"):
			completed += 1
		elif cycled:
			cycles.append(code)
			_assert_true([71, 87].has(int((run["pending"] as Dictionary).get("event", 0))), "event %d cycles through a ritual select (71 / 87)" % code)
		for entry in run["records"]:
			if str((entry as Dictionary).get("status", "")) == "unknown_token":
				unknown += 1
	_assert_eq(unknown, 0, "no unknown te token in the corpus")
	_assert_eq(completed, 174, "174 events complete under the auto-driver")
	_assert_eq(cycles, [53, 54, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 77, 79, 80, 87], "the 命運神殿 job-up chains cycle (no exit in the data under the fail-branch reading)")
