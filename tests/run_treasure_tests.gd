extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Gol = preload("res://tests/run_gol_road_tests.gd")
const Campaign = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "HSL-Treasure-Tests-" + str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")


static func initial(level: int = 2) -> Dictionary:
	var path := "res://content/battles/ohm_village_battle.json" if level == 1 else "res://content/battles/gol_road_battle.json"
	return Loop.initialize_roster_growth(Loop.create([], "", Loop.BattleScenario.load_file(path)))


static func placed(level: int = 2, id: String = "hu", box: int = 1) -> Dictionary:
	var loop := initial(level)
	var actor := Loop._unit(loop, id)
	var coord: Vector2i = loop["treasure_source"]["chests"][box]["coord"]
	actor["coord"] = coord
	actor["ai_home_coord"] = coord
	return Gol.owned_turn(loop, id)


static func meta(loop: Dictionary) -> Dictionary:
	return {"camera": Vector2(320, 300), "shown_story_events": [], "story_complete": true, "growth_notified_level": 4,
		"script_cutscene_consumed": loop.get("winfail_runtime", {}).get("fired", []).size(),
		"treasure_presented_sequence": loop.get("treasures", {}).get("receipts", []).size()}


static func defer_loot(loop: Dictionary) -> Dictionary:
	return Loop.finish_rewards(loop, loop["settlement"]["sequence"], loop["settlement"]["revision"], false, true)


static func claim_first(loop: Dictionary, id: String, slot: int = -1, expected: int = 0) -> Dictionary:
	return Loop.claim_reward(loop, loop["settlement"]["sequence"], loop["settlement"]["revision"], loop["settlement"]["pending"][0]["id"], id, slot, expected)


func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("Treasure tests timed out"); quit(2))
	var loop := initial()
	check(loop["scenario_ok"] and loop["treasure_source"]["chests"].size() == 2, "formal Gol loads only its two real source chests")
	check(loop["treasure_source"]["chests"][0]["items"] == [244, 244, 254], "duplicate original MP medicines remain two items, not a chance or a deduplicated set")
	check(not BattleFixture.loop().has("treasure_source"), "no chests or default grants leak into the first prologue battle")
	if not loop["scenario_ok"]: quit(1); return
	movement_and_pickup()
	full_bag_extra_action_and_combat()
	eligibility_and_terminals()
	carry_and_validation()
	await presentation_and_restore()
	print("TREASURE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func movement_and_pickup() -> void:
	var loop := placed()
	var chest: Dictionary = loop["treasure_source"]["chests"][1]
	var actor := Loop._unit(loop, "hu")
	actor["coord"] = chest["coord"] + Vector2i(0, 1)
	actor["ai_home_coord"] = actor["coord"]
	loop = Gol.owned_turn(loop, "hu")
	var before := loop.duplicate(true)
	var moved := Loop.move_unit_to(Loop.choose_command(loop, "move"), chest["coord"])
	check(moved["pending_move"] and Loop.unit(moved, "hu")["coord"] == chest["coord"], "normal legal movement can stop on a chest without inventing a blocking actor")
	check(moved["treasures"] == before["treasures"] and moved["settlement"].is_empty(), "reversible movement and preview do not award a chest")
	var cancelled := Loop.cancel_pending_move(moved)
	check(Loop.unit(cancelled, "hu")["coord"] == actor["coord"] and cancelled["treasures"] == before["treasures"], "cancelled movement restores origin with no reward, RNG or opened flag")
	var saved_move := Save.encode(moved, meta(moved))
	check(saved_move["ok"], "pre-pickup provisional movement is checkpointable")
	var found := Loop.begin_wait_resolution(moved)
	check(found["scenario_ok"] and Loop.loot_waiting(found), "actual Wait commits the source chest and opens the shared pending-item transaction")
	check(found.get("last_combat", {}).is_empty() and found["settlement"]["combat_sequence"] == 0, "opening a chest never fabricates an attack or death receipt")
	check(found["settlement"]["pending"].map(func(item): return item["code"]) == [2, 241], "the actual Gol EVEF contents are queued once in source order")
	check(found["turn_queue"] == moved["turn_queue"] and found["extra_action"] == moved["extra_action"] and found["action_end_sequence"] == moved["action_end_sequence"], "collection holds the completed action before next action/status/resource tail")
	for key in ["gold", TestSuite.STREAM_KEYS["reward"], TestSuite.STREAM_KEYS["global"], TestSuite.STREAM_KEYS["damage"]]:
		check(found[key] == moved[key], "treasure does not invent gold or consume a random stream: " + key)
	check(Loop.unit(found, "hu")["inventory"] == actor["inventory"], "discovery queues items rather than silently filling or replacing the actor bag")
	check(Loop.step_ai_turn(found) == found and Loop.begin_wait_resolution(found) == found, "duplicate action/AI calls cannot bypass pending treasure or grant it again")
	var unseen := meta(found); unseen["treasure_presented_sequence"] = 0
	check(not Save.encode(found, unseen)["ok"], "save cannot claim the unplayed discovery cue has finished")
	var saved := Save.encode(found, meta(found))
	check(saved["ok"], "post-cue treasure/held-action boundary can be saved: " + str(saved.get("reason", "")))
	if saved["ok"]:
		var restored := Save.decode(saved["bytes"], found)
		check(restored["ok"] and restored["snapshot"]["loop"] == found, "F9 preserves exact chest state, loot and the pending owner continuation")
		var claimed := claim_first(restored["snapshot"]["loop"], "hu")
		check(Loop.unit(claimed, "hu")["inventory"].count(2) == actor["inventory"].count(2) + 1, "first real confirmation transfers exactly one source weapon")
		check(Loop.claim_reward(claimed, found["settlement"]["sequence"], 0, found["settlement"]["pending"][0]["id"], "hu") == claimed, "old pre-claim revision cannot transfer twice")
		var resumed := Loop.step_ai_turn(defer_loot(claimed))
		check(resumed["treasures"]["receipts"].size() == 1 and not Loop.Treasure.awaiting_handoff(resumed), "finishing the modal resumes the existing action once without rediscovery")
		check(resumed["action_end_sequence"] == found["action_end_sequence"] + 1, "the held action receives exactly one final tail")


func full_bag_extra_action_and_combat() -> void:
	var loop := placed(1, "leonard", 0)
	var actor := Loop._unit(loop, "leonard")
	actor["inventory"] = [241, 241, 241, 241, 241, 241, 241, 241]
	actor["equipment"] = actor["equipment"].filter(func(row): return row["slot"] != "accessory2")
	actor["equipment"].append({"slot": "accessory2", "item_code": 227})
	actor["permanent_gains"]["attack_power"] = 3
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"]), true)
	actor.merge(Loop.StatusEffectRules.apply(actor, "no_magic", 2)["changes"], true)
	var before := loop.duplicate(true)
	var found := Loop.begin_wait_resolution(loop)
	check(found["scenario_ok"] and Loop.loot_waiting(found), "silence and a full bag do not prevent physical treasure discovery")
	check(claim_first(found, "leonard") == found, "full-bag auto-insert rejects without consuming an item or changing the transaction")
	var swapped := claim_first(found, "leonard", 0, 241)
	check(Loop.unit(swapped, "leonard")["inventory"].has(202) and swapped["settlement"]["pending"][0]["code"] == 241, "confirmed exchange retains the displaced medicine in the same pending pool")
	check(Loop.unit(swapped, "leonard")["permanent_gains"] == actor["permanent_gains"] and Loop.unit(swapped, "leonard")["equipment"] == actor["equipment"], "picking up equipment neither equips it nor reapplies permanent or worn modifiers")
	var second := Loop.step_ai_turn(defer_loot(swapped))
	check(second["selected_unit_id"] == "leonard" and second["extra_action"]["pending"] and not second["moved_this_action"], "White Wings grants its genuine independent second action only after collection is closed")
	check(second["action_end_sequence"] == before["action_end_sequence"] and Loop.unit(second, "leonard")["status_counters"] == actor["status_counters"], "first-action chest collection does not tick silence or apply a second resource tail")
	var victim := Loop._unit(second, "enemy028_1")
	if victim.is_empty():
		victim = second["units"].filter(func(unit): return unit["actor_id"] == "028")[0]
	victim["hp"] = 1
	victim["inventory"] = [281, 0, 0, 0, 0, 0, 0, 0] # Important guaranteed-drop fixture, not formal default loot.
	var hitter := Loop._unit(second, "leonard")
	hitter["hit_bonus_accum"] = 1000
	for offset in Loop.weapon_pattern(second, hitter)["offsets"]:
		victim["coord"] = hitter["coord"] + Vector2i(int(offset[0]), int(offset[1]))
		if Loop.TraversalRules.placement_error(victim, second["units"], second["tiles"], second["map_size"]) == "": break
	victim["ai_home_coord"] = victim["coord"]
	var attacked := Loop.attack_target(Loop.choose_command(second, "attack"), victim["id"], func(_bound): return 0)
	check(attacked["last_combat"].get("defender_id") == victim["id"] and Loop.unit(attacked, victim["id"])["defeated"], "a real lethal attack still resolves after the earlier chest transaction")
	check(attacked["settlement"]["sequence"] > swapped["settlement"]["sequence"] and attacked["settlement"]["combat_sequence"] == attacked["last_combat"]["sequence"], "reward transaction sequence advances independently from the first actual combat sequence")
	check(attacked["settlement"]["pending"].any(func(item): return item["code"] == 281) and attacked["settlement"]["pending"].any(func(item): return item["id"] == found["settlement"]["pending"][0]["id"]), "subsequent kill loot and deferred exchanged chest items both survive")
	check(Loop.claim_reward(attacked, swapped["settlement"]["sequence"], swapped["settlement"]["revision"], found["settlement"]["pending"][0]["id"], "leonard") == attacked, "old chest confirmations cannot claim from the next combat transaction")
	var finish := Loop.finish_exhausted_action(defer_loot(attacked))
	check(finish["treasures"]["receipts"].size() == 1 and finish["action_end_sequence"] == before["action_end_sequence"] + 1 and not finish["extra_action"]["pending"], "second completed action does not open the box again, grant a third action or duplicate the final tail")
	check(Loop.Treasure.settlement_error(finish) == "", "mixed chest/kill settlement retains explicit provenance")


func eligibility_and_terminals() -> void:
	var loop := placed()
	var paralyzed := loop.duplicate(true)
	var owner := Loop._unit(paralyzed, "hu")
	owner.merge(Loop.StatusEffectRules.apply(owner, "paralysis", 2)["changes"], true)
	paralyzed["interaction"] = "ai_resolving"; paralyzed["selected_unit_id"] = ""
	var skipped := Loop.step_ai_turn(paralyzed)
	check(skipped["treasures"]["opened_ids"].is_empty() and skipped["action_end_sequence"] == paralyzed["action_end_sequence"] + 1, "paralysis skip gets its established single tail but no treasure action")
	var npc := loop.duplicate(true)
	var actor := Loop._unit(npc, "hu")
	actor["player_commandable"] = false; actor["battle_actor_role"] = Loop.ROLE_FRIENDLY
	npc["interaction"] = "ai_resolving"; npc["selected_unit_id"] = ""
	var unclaimed := Loop._advance_current_actor(npc)
	check(unclaimed["treasures"]["opened_ids"].is_empty(), "AI control does not take party treasures through the player-only completion adapter")
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED, BattleOutcome.DEFEAT_FALLEN, BattleOutcome.VICTORY_ESCAPE]:
		var terminal := loop.duplicate(true)
		terminal["battle_outcome"] = outcome; terminal["interaction"] = "battle_result"
		check(Loop.begin_wait_resolution(terminal) == terminal and Loop.step_ai_turn(terminal) == terminal and Loop.finish_exhausted_action(terminal) == terminal, "existing terminal states never start post-freeze chest transactions: " + BattleOutcome.describe(outcome))
	check(initial()["treasures"]["opened_ids"].is_empty(), "fresh restart initializes the source chest state, not old awards")
	var missing := Loop.BattleScenario.load_file("res://content/battles/gol_road_battle.json")
	missing["resources"]["treasures"] = "res://absent_treasure.json"
	check(not Loop.create([], "", missing)["scenario_ok"], "missing required contents fail explicitly rather than inventing a reward")


func carry_and_validation() -> void:
	var found := Loop.begin_wait_resolution(placed())
	for kind in ["opened", "contents", "rng", "owner", "sequence"]:
		var bad := found.duplicate(true)
		match kind:
			"opened": bad["treasures"]["opened_ids"].clear()
			"contents": bad["treasures"]["receipts"][0]["items"][0]["code"] = 244
			"rng": bad["treasures"]["receipts"][0]["rng_consumed"] = 1
			"owner": bad["treasures"]["handoff"]["actor_id"] = "leonard"
			"sequence": bad["settlement"]["combat_sequence"] = 99
		check(not Save.encode(bad, meta(bad))["ok"], "restore rejects a contradictory chest transaction: " + kind)
	for index in [-1, found["turn_queue"]["slots"].size(), 0.5]:
		var bad := found.duplicate(true)
		bad["turn_queue"]["index"] = index
		bad["treasures"]["handoff"]["queue_index"] = index
		check(not Save.encode(bad, meta(bad))["ok"], "held chest queue rejects invalid indices before array access")
	for cursor in [0.5, "0"]:
		var bad := found.duplicate(true)
		bad["settlement"]["combat_sequence"] = cursor
		check(not Save.encode(bad, meta(bad))["ok"], "chest provenance rejects fractional and string combat cursors rather than truncating them")
	var deferred := defer_loot(found)
	var carry: Dictionary = JSON.parse_string(JSON.stringify(Loop.CampaignCarryRules.capture(deferred)))
	check(carry.has("pending_rewards") and carry["pending_rewards"]["items"].size() == 2, "deferred items are included in real campaign JSON rather than lost at a scene boundary")
	var next := Loop.create([], "", Loop.BattleScenario.load_file("res://content/battles/gol_road_battle.json"))
	next = Loop.initialize_roster_growth(Loop.apply_campaign_carry(next, carry))
	check(next["scenario_ok"] and next["settlement"].get("source_kind") == "campaign" and Loop.loot_waiting(next), "next battle restores the old pending pool without pretending it was a fresh kill")
	check(Loop.unit(next,"hu")["inventory"].all(func(code):return typeof(code)==TYPE_INT), "JSON-carried slots are validated and normalized before menus or AI use them")
	check(next["treasures"]["opened_ids"].is_empty() and next["settlement"]["pending"].all(func(item): return str(item["id"]).begins_with("carry:")), "new visit chest identities stay separate from old unclaimed rewards")
	next = Loop.begin_battle(next)
	check(Save.encode(next, meta(next))["ok"], "carried pending items have a valid independent checkpoint provenance")
	check(not Loop.CampaignCarryRules.initialization_only(carry).has("pending_rewards"), "separate-party transitions preserve isolation and never give another party its pending items")
	var invalid := carry.duplicate(true)
	invalid["pending_rewards"]["items"][0]["code"] = 999999
	var fresh := Loop.create([], "", Loop.BattleScenario.load_file("res://content/battles/gol_road_battle.json"))
	var failed := Loop.CampaignCarryRules.apply(fresh, invalid)
	check(failed["units"] == fresh["units"] and failed["settlement"].is_empty() and failed["campaign_carry_receipt"]["errors"].has("invalid_carry_pending_rewards"), "invalid carried item rejects before actor/inventory or stream changes")


func presentation_and_restore() -> void:
	var runtime = load("res://game/battle/development/GolRoad.tscn").instantiate()
	runtime.startup_mode = "dev_first_control"
	root.add_child(runtime)
	await create_timer(0.15).timeout
	runtime.set_process(false)
	runtime.apply_loop(Loop.begin_wait_resolution(placed()), "test")
	runtime.interaction_state = runtime.play_loop["interaction"]
	var treasure: Node = runtime.treasure_view
	var chest: Dictionary = runtime.play_loop["treasure_source"]["chests"][1]
	var nodes: Array = treasure.box_nodes(chest)
	# Gol's chests are original hidden treasure (shape word 0xffff at round 1, original_treasure.md §隐藏宝物).
	check(nodes.size() == 1 and chest["hidden"] and not nodes[0].visible, "formal source box resolves to its existing map sprite, not drawn while it is hidden treasure")
	runtime._process(0.0)
	check(treasure.busy() and not runtime.settlement_controller.panel.visible and not runtime.settlement_controller.quiet(), "discovery fade/audio holds input, saving and the loot modal")
	check(runtime.ui_audio.stream.resource_path.ends_with("interface_audio/get_treasure.wav"), "finding hidden treasure plays the original sfxGetTreasure (0x445526 → 0x4477b0(0xa05))")
	runtime._process(1.0); runtime._process(0.0)
	var panel: Control = runtime.settlement_controller.panel
	check(not nodes[0].visible and panel.visible and panel._recipient == "hu", "after the cue, opened source box disappears and real collection controls select its actor")
	var before: Dictionary = runtime.play_loop.duplicate(true)
	panel.rows[0].pressed.emit()
	var stale: Button = panel.slots[panel.first_empty_slot()]
	panel.cancel(); stale.pressed.emit()
	check(runtime.play_loop == before, "returning the held item to the list leaves the bag-slot click inert")
	var controller: Node = runtime.settlement_controller
	controller.checkpoint_path = "user://treasure-test.save"
	check(controller.save_battle()["ok"], "real controller saves exact post-cue pending collection")
	check(controller.load_battle()["ok"] and runtime.play_loop == before and not treasure.busy() and not nodes[0].visible, "real F9 restores an opened box without replaying fade, sound or grants")
	# Old valid checkpoints can still contain JSON-origin numeric item slots.
	# Ask the same inventory proposal as the rule instead of treating 0.0 as full.
	var json_actors: Array=JSON.parse_string(JSON.stringify(panel._actors))
	panel.close(); panel.show_rewards(before["settlement"],json_actors,before["equipment_items"],int(before["gold"]))
	panel.rows[0].pressed.emit()
	check(panel.holding() and panel.first_empty_slot() >= 0 and runtime.play_loop==before,"old integral-float inventory still offers a legal free slot to the held item without committing a pickup")
	check(controller.load_battle()["ok"],"restoring cancels the legacy-slot preview without a transfer")
	var presentation: Node = runtime.get_node("BattlePresentation")
	presentation._dialogue_messages.append({"speaker_id":"2", "message_id":"743", "text":runtime.message_text_evidence["messages"]["743"]})
	presentation._update_dialogue_page()
	check(presentation.dialogue_view.visible and presentation.dialogue_view.speaker_label.text.contains("琥") and presentation.dialogue_view.portrait.texture != null, "real Gol defeat speaker2 resolves source003 portrait instead of dropping the dialogue")
	presentation._dialogue_messages.clear(); presentation._update_dialogue_page()
	# A complete source victory with deferred treasure must remain reachable in
	# the product UI, not only through a direct prepare_handoff unit test.
	var won := Loop.step_ai_turn(defer_loot(before))
	won = Loop._resolve_outcome(Gol.Rules.run_event_hooks(Gol.ready_event(won)))
	var guards: Array = won["units"].filter(func(a):return a["actor_id"]=="023")
	for index in range(1,guards.size()): Loop._set_unit_defeated(won,guards[index]["id"],true)
	won = Loop._resolve_outcome(won)
	runtime.apply_loop(won, "test"); runtime.interaction_state = won["interaction"]
	runtime.script_cutscene_consumed = won["winfail_runtime"]["fired"].size()
	presentation.battle_finished = true; treasure.restore(won["treasures"]["receipts"].size())
	controller.tick()
	var progress: Node = runtime.campaign_progress
	progress._process(0.0)
	check(not progress.deferred_rewards_ready() and controller.panel.visible,"victory's reopened loot must be explicitly finished before deferred continuation")
	controller.panel.finish_button.pressed.emit()
	controller.tick(); progress._process(0.0)
	check(progress.deferred_rewards_ready() and not progress.hold_for_loot(),"quiet deferred victory continues with its pool without holding the battle end: quiet=%s" % controller.quiet())
	var handoff: Dictionary = progress.prepare_handoff()
	check(handoff["carry"].get("pending_rewards",{}).get("items",[]).size()==won["settlement"]["pending"].size(),"real campaign adapter carries every deferred source item")
	Campaign.pending={}
	controller.open_rewards(); progress._process(0.0)
	progress.start_next_battle()
	check(Campaign.pending.is_empty(),"open pickup interaction cannot be bypassed by a stale continue action")
	runtime.apply_loop(defer_loot(runtime.play_loop), "test");controller.tick();progress._process(0.0)
	progress.start_next_battle()
	check(Campaign.pending.get("scenario_path","").ends_with("story_055.json") and Campaign.pending["carry"]["pending_rewards"]==handoff["carry"]["pending_rewards"],"validated defer enables the actual next-battle action without losing the pool")
	Campaign.pending={}
	progress.campaign["battles"]["2"]["party"]="separate"
	progress._process(0.0); progress.start_next_battle()
	check(Campaign.pending.is_empty(),"separate party cannot silently pass its own unclaimed items into another party")
	# A carried reward pool can precede an NPC's first slot. The development
	# fast-forward must yield to loot, not repeatedly ask a correctly blocked AI.
	var waiting:=Loop.begin_wait_resolution(placed())
	var carried: Dictionary=JSON.parse_string(JSON.stringify(Loop.CampaignCarryRules.capture(defer_loot(waiting))))
	var fresh:=Loop.initialize_roster_growth(Loop.apply_campaign_carry(Loop.create([],"",Loop.BattleScenario.load_file("res://content/battles/gol_road_battle.json")),carried))
	for index in range(fresh["turn_queue"]["slots"].size()):
		if not Loop.unit(fresh,fresh["turn_queue"]["slots"][index]["id"])["player_commandable"]:
			fresh["turn_queue"]["index"]=index; break
	runtime.apply_loop(fresh, "test")
	runtime.enter_first_control_state("dev_first_control_harness")
	check(Loop.loot_waiting(runtime.play_loop) and runtime.play_loop["settlement"]==fresh["settlement"] and runtime.play_loop["turn_queue"]==fresh["turn_queue"],"dev entry yields at carried loot before the first NPC instead of looping or spending its action")
	controller.tick()
	check(controller.panel.visible,"carried loot remains a real visible control at the development entry boundary")
	for player in runtime.find_children("*", "AudioStreamPlayer", true, false): player.stop(); player.stream = null
	await create_timer(0.15).timeout
	root.remove_child(runtime); runtime.queue_free()
	await process_frame; await create_timer(0.3).timeout


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)
