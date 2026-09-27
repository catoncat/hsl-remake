extends SceneTree

## Headless coverage of tests/support/AutoplayShopping.gd, the chapter autoplay's town shopper:
## in 歐姆村's weapon shop (長劍 / 木杖 / 匕首) a carried 雷歐納德 with an empty weapon slot buys
## the 長劍 (code 1, 200 gold; the staff and dagger are not a swordsman's) and wears it through
## PartyEquipmentRules; a member already wearing it buys nothing; the item shop fills
## the bag to POTIONS_PER_MEMBER 回復藥 and no further; a shop selling nothing better buys
## nothing; too little gold skips the piece; HSL_AUTOPLAY_GOLD=unlimited buys it anyway and
## leaves the carry's gold as it was. Restocking comes before gear: a weapon shop leaves the gold
## that topping the bag up to POTIONS_PER_MEMBER 回復藥 would cost (300 gold with 2 回復藥 held
## keeps 200 back, so the 200-gold 長劍 is not bought), and the item shop never fills the bag's
## last free slot (a new piece of gear goes into the bag before it is worn). The town is TownRuntime hosted by WorldMapRuntime, as in
## run_town_scene_tests.gd; prices and rules are the product's own, the policy is the harness's.

const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const MapRules = preload("res://game/world/WorldMapRules.gd")
const TownRules = preload("res://game/sim/TownEventRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const Shopping = preload("res://tests/support/AutoplayShopping.gd")

const SCENE_PATH := "res://content/world/world_map_scene.json"
const WORLD_MAP_PATH := "res://content/imported/hsl/global/world_map/world_map.json"
const TOWNDEF_PATH := "res://content/imported/hsl/global/world_map/towndef.json"
const TREES_PATH := "res://content/world/town_initial_trees.json"
## 歐姆村's scenario id: the carry's equipment sandbox template (PartyEquipmentRules).
const OHM_VILLAGE_SCENARIO_ID := "battle_004_level1"
const WEAPON_SHOP := 1
const ITEM_SHOP := 3
const LONG_SWORD := 1
const POTION := 241

var failures: Array[String] = []
var campaign: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


## 雷歐納德 at level 3 with `inventory` in the bag, `gold` on hand and `equipment` worn
## (empty: bare weapon slot, weapon_code 0).
func _carry(gold: int, inventory: Array, equipment: Array = []) -> Dictionary:
	var weapon_code := EquipmentRules.equipped_code(equipment, "weapon")
	return {"schema": "hsl_campaign_carry.v1", "from_scenario_id": OHM_VILLAGE_SCENARIO_ID, "from_outcome": "",
		"units": {"leonard": {"actor_id": "001", "level": 3, "inventory": inventory, "attributes": {}, "equipment": equipment, "weapon_code": weapon_code}},
		"loop": {"gold": gold}, "restore_vitals": true}


func _long_sword_worn() -> Array:
	return [{"slot": "weapon", "item_code": LONG_SWORD, "name": "長劍"}]


func _fresh_state(start_point: int) -> Dictionary:
	var world_map := MapRules.load_world_map(WORLD_MAP_PATH)
	var towns := TownRules.initial_town_state(TownRules.load_towndef(TOWNDEF_PATH), TownRules.load_initial_trees(TREES_PATH))
	var state := MapRules.initial_state(world_map, start_point, towns)
	state["secret_roll"] = 100
	return state


func _boot(carry: Dictionary) -> Node:
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": SCENE_PATH, "carry": carry, "from_scenario_id": OHM_VILLAGE_SCENARIO_ID, "world": _fresh_state(1)}
	CampaignProgress.last_entry = {}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = SCENE_PATH
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


## Opens 歐姆村 and its shop `entry` (root menu code), confirming the keeper's greeting.
func _open_shop(scene: Node, entry: int) -> Node:
	scene.world_map_runtime.select_point(1, "test")
	await process_frame
	var town = scene.world_map_runtime.town_runtime
	_assert_true(town != null and str(town.mode) == "menu", "歐姆村 opens on its root menu")
	if town == null:
		return null
	town.select_entry(entry)
	var guard := 0
	while str(town.mode) in ["dialogue", "delay"] and guard < 40:
		town.confirm()
		guard += 1
	_assert_eq(str(town.mode), "shop", "root entry %d opens a shop" % entry)
	return town


func _teardown(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


func _worn(town: Node, slot: String) -> int:
	return EquipmentRules.equipped_code((town.carry["units"]["leonard"] as Dictionary).get("equipment", []), slot)


func _bag(town: Node) -> Array:
	return (town.carry["units"]["leonard"] as Dictionary).get("inventory", [])


func _run() -> void:
	campaign = CampaignProgress.load_campaign()
	CampaignProgress.resume_prompt_in_headless = false
	OS.set_environment(Shopping.GOLD_ENV, "")
	await _run_weapon_shop()
	await _run_item_shop()
	await _run_short_gold()
	await _run_unlimited_gold()
	await _run_restock_first()
	OS.set_environment(Shopping.GOLD_ENV, "")
	await process_frame
	await process_frame
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.2))
	if failures.is_empty():
		print("AUTOPLAY_SHOPPING_PASS cases=6")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AUTOPLAY_SHOPPING_FAIL count=%d" % failures.size())
		quit(1)


func _run_weapon_shop() -> void:
	var scene = await _boot(_carry(1000, [POTION, POTION, 0, 0, 0, 0, 0, 0]))
	var town = await _open_shop(scene, WEAPON_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_true(bool(receipt["ok"]), "the shopper runs on a carried party: %s" % str(receipt["reason"]))
		_assert_eq(int(receipt["gold_before"]), 1000, "gold before")
		var purchases: Array = receipt["purchases"]
		_assert_eq(purchases.size(), 1, "one purchase in the weapon shop (長劍 for the bare slot; 木杖 / 匕首 are not the swordsman's)")
		if purchases.size() == 1:
			_assert_eq(int(purchases[0]["item"]), LONG_SWORD, "長劍 bought")
			_assert_eq(str(purchases[0]["slot"]), "weapon", "for the weapon slot")
			_assert_eq(bool(purchases[0]["equipped"]), true, "and worn at once")
			_assert_eq(int(purchases[0]["sold"]), 0, "nothing taken off, nothing sold")
		_assert_eq(_worn(town, "weapon"), LONG_SWORD, "the carry's equipment holds the 長劍")
		_assert_eq(int((town.carry["units"]["leonard"] as Dictionary).get("weapon_code", 0)), LONG_SWORD, "the carry's weapon code follows")
		_assert_eq(_bag(town), [POTION, POTION, 0, 0, 0, 0, 0, 0], "the bag holds the potions only (the sword is worn, not carried)")
		_assert_eq(int(receipt["gold_after"]), 800, "1000 - 200")
		_assert_eq(int(town.party_gold()), 800, "the town shows the same gold")
		_assert_eq(int((scene.campaign_handoff["carry"]["units"]["leonard"] as Dictionary).get("weapon_code", 0)), LONG_SWORD, "the hand-off carry took the change (party_changed)")
		var again := Shopping.shop(town, campaign)
		_assert_eq((again["purchases"] as Array).size(), 0, "a second visit finds nothing better")
	await _teardown(scene)
	scene = await _boot(_carry(1000, [0, 0, 0, 0, 0, 0, 0, 0], _long_sword_worn()))
	town = await _open_shop(scene, WEAPON_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_eq((receipt["purchases"] as Array).size(), 0, "a member already wearing the 長劍 buys nothing here")
		_assert_eq(int(receipt["gold_after"]), 1000, "gold untouched")
	await _teardown(scene)


func _run_item_shop() -> void:
	var scene = await _boot(_carry(1000, [POTION, 0, 0, 0, 0, 0, 0, 0]))
	var town = await _open_shop(scene, ITEM_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		var purchases: Array = receipt["purchases"]
		_assert_eq(purchases.size(), Shopping.POTIONS_PER_MEMBER - 1, "the item shop tops the bag up to POTIONS_PER_MEMBER 回復藥")
		_assert_eq(_bag(town).count(POTION), Shopping.POTIONS_PER_MEMBER, "bag potion count")
		_assert_eq(int(receipt["gold_after"]), 1000 - 100 * (Shopping.POTIONS_PER_MEMBER - 1), "each 回復藥 costs 100")
	await _teardown(scene)


func _run_short_gold() -> void:
	var scene = await _boot(_carry(100, [0, 0, 0, 0, 0, 0, 0, 0]))
	var town = await _open_shop(scene, WEAPON_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_eq((receipt["purchases"] as Array).size(), 0, "100 gold buys no 200-gold 長劍")
		_assert_eq(_worn(town, "weapon"), 0, "the slot stays bare")
		_assert_eq(int(receipt["gold_after"]), 100, "gold untouched")
	await _teardown(scene)


func _run_unlimited_gold() -> void:
	OS.set_environment(Shopping.GOLD_ENV, Shopping.GOLD_UNLIMITED)
	var scene = await _boot(_carry(100, [0, 0, 0, 0, 0, 0, 0, 0]))
	var town = await _open_shop(scene, WEAPON_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_eq(str(receipt["gold_mode"]), Shopping.GOLD_UNLIMITED, "receipt names the knob")
		_assert_eq((receipt["purchases"] as Array).size(), 1, "unlimited gold buys the 長劍 with 100 on hand")
		_assert_eq(_worn(town, "weapon"), LONG_SWORD, "and wears it")
		_assert_eq(int(receipt["gold_after"]), 100, "the carry's gold is restored afterwards (purchases cost nothing)")
		_assert_eq(int(town.party_gold()), 100, "the town shows the restored gold")
	OS.set_environment(Shopping.GOLD_ENV, "")
	await _teardown(scene)


func _run_restock_first() -> void:
	var scene = await _boot(_carry(300, [POTION, POTION, 0, 0, 0, 0, 0, 0]))
	var town = await _open_shop(scene, WEAPON_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_eq((receipt["purchases"] as Array).size(), 0, "300 gold with 2 回復藥 held keeps 200 for the restock: the 200-gold 長劍 waits")
		_assert_eq(int(receipt["gold_after"]), 300, "gold untouched")
	await _teardown(scene)
	scene = await _boot(_carry(1000, [POTION, LONG_SWORD, LONG_SWORD, LONG_SWORD, LONG_SWORD, LONG_SWORD, 0, 0]))
	town = await _open_shop(scene, ITEM_SHOP)
	if town != null:
		var receipt := Shopping.shop(town, campaign)
		_assert_eq((receipt["purchases"] as Array).size(), 1, "two free slots: one 回復藥, the last slot stays free for gear")
		_assert_eq(_bag(town).count(0), 1, "one free bag slot left")
	await _teardown(scene)
