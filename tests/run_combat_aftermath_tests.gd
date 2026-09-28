extends SceneTree
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const LevelUpStars = preload("res://game/battle/scene/LevelUpStars.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void: call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)


func fixture() -> Node:
	# Every fixture boots from the seeded global stream, not from where the previous
	# fixture's opening and AI left the process stream (opening levels decide the gold).
	GlobalRandomStream.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	TestSuite.stop_audio(scene.get_node("BattleMusic"))
	scene.get_node("BattlePresentation").cutin.set_process(false)
	var player := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	player["live_speed"] = 100
	player["stamina"] = 60
	var next := BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
	next["growth_profile"]["source"]["speed"] += 99 - int(next["live_speed"])
	next.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(next,scene.play_loop["equipment_items"]),true)
	next["player_commandable"] = true
	next["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	var enemy := BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.UP
	enemy["hp"] = 1
	enemy["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0] # This suite isolates death/EXP/gold; loot has its own live tests.
	scene.play_loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(BattlePlayLoop.select_player_unit(scene.play_loop, "leonard"), "test")
	scene.ai_playback_active = false
	scene.interaction_state = "action_menu"
	scene.apply_loop(scene.play_loop, "test")
	return scene


func attack(scene: Node, command: String = "attack", missed: bool = false) -> void:
	scene.menus.choose_command(command)
	if command == "special": scene.menus._choose_magic("special:magicOTHER:magicCode01")
	scene.apply_loop(BattlePlayLoop.attack_target(scene.play_loop, "enemy021_1", func(n): return n - 1 if missed else 0), "test")
	scene.finish_attack_attempt()


func finish_cutin(scene: Node) -> void:
	var view = scene.get_node("BattlePresentation")
	scene._process(0)
	scene._process(view.attack_cue.duration)
	check(view.cutin.busy(), "an actual receipt enters the normal cutin")
	while view.cutin.busy(): view.cutin._process(100)
	scene._process(0)


## Death-sound players the presentation started for `unit_id` (BattlePresentation._play_sound
## on BattleAftermath.disposal_started — the one death-sound entry for every death source).
func death_sounds(scene: Node, unit_id: String) -> int:
	var view = scene.get_node("BattlePresentation")
	var path := ActorSpriteKey.audio_binding(BattlePlayLoop.unit(scene.play_loop, unit_id), "dead", [view.audio_manifest, view.shared_audio_manifest])
	check(path != "", "the death sound of %s is bound" % unit_id)
	var count := 0
	for child in view.get_children():
		if child is AudioStreamPlayer and child.stream != null and child.stream.resource_path == path: count += 1
	return count


## A player's Space. Under OPT-PACE 原版 the dialogue board reads no confirm while its page
## wipes in or scrolls (BattleDialogue.holds_confirm), so the player waits for the page to be
## still first: the boards' clocks are ticked until they take the key.
func confirm(scene: Node) -> void:
	for board in [scene.opening_overlay, scene.get_node("BattlePresentation").dialogue_view]:
		for _tick in 200:
			if not board.holds_confirm(): break
			board._process(preload("res://game/common/OriginalTick.gd").TICK_SECONDS)
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	scene._input(event)


func run() -> void:
	for command in ["attack", "special"]:
		for fps in [30, 144]:
			await lethal_case(command, fps)
	await counter_defeat()
	await map_magic()
	await map_magic_lead_pose()
	await multi_target()
	await terminal_victory()
	for skip in [false, true]:
		await terminal_victory_level_up(skip)
	await kill_loot_level_up_order()
	await installed_dead_message()
	dead_message_choice()
	await run_growth_offer()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("COMBAT_AFTERMATH_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


## The line the death branch shows for this victim in the aftermath's current exchange: the
## pair half chosen by the roll (0x43efaf structure; the roll is the remake's hash).
func expected_line(tail, unit_id: String, actor_id: String) -> String:
	var line: Dictionary = tail.choose_dead_message(tail.death_template(actor_id)["messages"], tail.dead_message_roll(tail.sequence, unit_id))
	return str(line.get("id", ""))


## 0x43ef91..0x43efcb on real PLAYERS rows: 021's pair (372／373 — the bridge soldier said
## "啊---！" at 140.99 s and "拉爾斯帝國萬歲！！" at 193.97 s in the original recording), 008's
## "1825,0" (a zero half takes the other), 001 (no dead_message: silence).
func dead_message_choice() -> void:
	var scene := fixture()
	var tail = scene.get_node("BattlePresentation").aftermath
	var pair: Array = tail.death_template("021")["messages"]
	check(pair.size() == 2 and str(tail.choose_dead_message(pair, 2)["id"]) == "372" and str(tail.choose_dead_message(pair, 7)["id"]) == "373", "an even roll picks the first listed half, an odd roll the second (0x458c10 & 1)")
	var lone: Array = tail.death_template("008")["messages"]
	check(lone.size() == 1 and str(tail.choose_dead_message(lone, 1)["id"]) == "1825" and str(tail.choose_dead_message(lone, 0)["id"]) == "1825", "a zero half (008 1825,0) is replaced by the other half whatever the roll")
	check(tail.death_template("001")["messages"].is_empty() and tail.choose_dead_message(tail.death_template("001")["messages"], 1).is_empty(), "a zero word (001) shows no last words")
	var both := {}
	for sequence in range(1, 41): both[str(tail.choose_dead_message(pair, tail.dead_message_roll(sequence, "enemy021_1"))["id"])] = true
	check(both.has("372") and both.has("373"), "over many exchanges the same soldier speaks both halves, as in the original recording")
	check(tail.dead_message_roll(5, "enemy021_1") == tail.dead_message_roll(5, "enemy021_1"), "the roll is deterministic: a reloaded exchange speaks the same line")
	scene.queue_free()


func sprite_path(actor: Node2D) -> String:
	var sprite := actor.get_node_or_null("Sprite2D") as Sprite2D
	return sprite.texture.resource_path if sprite != null and sprite.texture != null else ""


func lethal_case(command: String, fps: int) -> void:
	var scene := fixture()
	var view = scene.get_node("BattlePresentation")
	var tail = view.aftermath
	var deaths: Array = []
	var rewards: Array = []
	tail.disposal_started.connect(func(unit): deaths.append(str(unit["actor_id"])))
	tail.experience_presented.connect(func(growth): rewards.append(growth))
	var level_ups: Array = []
	tail.level_up_presented.connect(func(growth): level_ups.append(growth))
	BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["exp"] = 99
	scene._process(0)
	check(RuntimeReadback.highlight_kind(scene.actor_node_for_unit("leonard")) == "actor" and RuntimeReadback.highlight_kind(scene.actor_node_for_unit("enemy021_1")) == "", "the unit choosing its command carries the actor highlight")
	scene.menus.choose_command(command)
	if command == "special": scene.menus._choose_magic("special:magicOTHER:magicCode01")
	scene.hovered_unit_id = "enemy021_1"
	scene.hovered_grid_cell = BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["coord"]
	scene._process(0)
	scene._process(0)
	check(scene.interaction_state == "attack_select" and RuntimeReadback.highlight_kind(scene.actor_node_for_unit("enemy021_1")) == "target", "the legal target under the target cursor carries the target highlight (%s, %s)" % [scene.interaction_state, RuntimeReadback.highlight_kind(scene.actor_node_for_unit("enemy021_1"))])
	attack(scene, command)
	var settled: Dictionary = scene.play_loop.duplicate(true)
	var actor: Node2D = scene.actor_node_for_unit("enemy021_1")
	check(actor.visible and BattlePlayLoop.unit(settled, "enemy021_1")["defeated"], "logical death stays visible before its exchange")
	scene._process(0)
	scene._process(view.attack_cue.duration)
	view.cutin._process(1.8)
	check(not tail.reward_label.visible and not view.dialogue_active() and not scene.ui_audio.playing, "cutin cannot expose map reward, last words or upgrade sound")
	check(not view.cutin.result.text.contains("EXP"), "EXP is not duplicated inside the combat close-up")
	while view.cutin.busy(): view.cutin._process(100)
	scene._process(0)
	check(view.dialogue_active() and view.current_message_id() == expected_line(tail, "enemy021_1", "021") and actor.visible, "source last words (the pair half the death-branch roll picks) begin on the map with victim retained")
	check(scene.play_loop == settled and not scene.growth_panel.visible, "last words cannot change HP/EXP or open allocation early")
	# 0x446c40(actor, facing, 6, 2) at the death entry: state 6 is the SHAPEDEF hit frame (021-P).
	check(sprite_path(actor).ends_with("/021-P.png"), "the fallen actor shows its SHAPEDEF hit pose through its last words (%s)" % sprite_path(actor))
	check(RuntimeReadback.highlight_kind(actor) == "" and RuntimeReadback.highlight_kind(scene.actor_node_for_unit("leonard")) == "", "no target／actor highlight while the last words are up")
	for _frame in range(fps): scene._process(1.0 / fps)
	check(tail.dialogue_active() and deaths.is_empty() and death_sounds(scene, "enemy021_1") == 0 and rewards.is_empty(), "refresh waits for confirmation; the death sound waits for the last words")
	scene.menus.choose_command("wait")
	scene.select_actor("enemy023_1")
	check(scene.play_loop == settled and not scene.action_menu.visible, "stale command/selection cannot act behind death dialogue")
	confirm(scene)
	check(tail.stage == "fade" and not view.dialogue_active(), "one normal confirmation releases only this death page")
	check(deaths == ["021"] and death_sounds(scene, "enemy021_1") == 1, "the death sound starts once as the stretch begins, after the last words (sub-state 0 0x409700)")
	scene._process(tail.FADE_SECONDS / 2)
	check(actor.visible and actor.modulate.a > 0 and actor.modulate.a < 1, "the map actor visibly fades after its last words")
	# 0x43f0cd: each of the 16 ticks the vertical zoom grows 0.25 and the level drops 1 — halfway
	# the actor stands 3× tall from its foot anchor, half faded, drawn additively.
	check(sprite_path(actor).ends_with("/021-P.png"), "the stretch draws the hit pose")
	check(is_equal_approx(tail.FADE_SECONDS, 16 * 0.016) and absf(actor.scale.y - 3.0) < 0.3 and actor.scale.x == 1.0 and absf(actor.modulate.a - 0.5) < 0.1 and actor.material == preload("res://game/battle/scene/AdditiveLevelBlend.gd").material(), "the death disposal stretches the actor upward while it fades, additively (scale %s alpha %.2f)" % [str(actor.scale), actor.modulate.a])
	confirm(scene)
	check(scene.play_loop == settled, "confirmation during fade cannot consume the successor")
	scene._process(tail.FADE_SECONDS)
	check(not actor.visible and not tail.reward_label.visible, "dead actor leaves before the reward stage")
	check(actor.scale == Vector2.ONE and actor.material == null, "the hidden actor's stretch and blend are undone")
	scene._process(0)
	# 0x442720: EXP (phase 0) → $ (phase 2) → LEVEL UP with sfxLevelUp (phase 6) → the window (phase 8).
	check(tail.reward_label.visible and tail.reward_label.text == "EXP %d" % int(settled["last_attack"]["experience"]["gained"]), "map reward displays the committed final native EXP receipt")
	check(rewards.size() == 1 and level_ups.is_empty() and not scene.ui_audio.playing, "the EXP float carries no level-up cue")
	for _frame in range(fps / 2): scene._process(1.0 / fps)
	check(not scene.ui_audio.playing and rewards.size() == 1 and scene.play_loop == settled, "reward animation remains read-only and cannot replay its cue")
	scene._process(tail.REWARD_SECONDS)
	scene._process(0)
	check(tail.reward_label.text == "$ 100" and scene.play_loop == settled and not scene.growth_panel.visible and level_ups.is_empty(), "settled money follows EXP and still blocks growth")
	scene._process(tail.REWARD_SECONDS)
	scene._process(0)
	check(tail.reward_label.visible and tail.reward_label.text == "LEVEL UP" and level_ups.size() == 1 and scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("level_up.wav") and not scene.growth_panel.visible, "the LEVEL UP float follows the money with the level-up sound, before the window")
	# 0x442720 phase 6: 0x4071e0 poses the recipient, 0x4084e0 kind 6 scatters the stars (R7-POSE).
	var recipient: Node2D = scene.actor_node_for_unit("leonard")
	check(recipient.is_posing() and sprite_path(recipient).ends_with("/001-M0001.png"), "the recipient takes its use_magic pose with the LEVEL UP float (%s)" % sprite_path(recipient))
	var showers: Array = tail.trailing.filter(func(entry): return entry["node"] is LevelUpStars)
	check(showers.size() == 1 and showers[0]["node"].stars.size() == 36 and showers[0]["coord"] == BattlePlayLoop.unit(settled, "leonard")["coord"] and showers[0]["node"].visible, "36 LEVEL UP stars rise over the recipient")
	scene.ui_audio.stop()
	for _frame in range(fps / 4): scene._process(1.0 / fps)
	check(not scene.ui_audio.playing and level_ups.size() == 1, "the level-up sound plays once")
	scene._process(tail.REWARD_SECONDS)
	check(not tail.busy() and scene.growth_panel.visible and scene.play_loop == settled, "allocation opens only after the final reward, before action handoff")
	for _point in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
		scene.growth_panel.choices["con"]["plus"].pressed.emit()
	scene.growth_panel.confirm_button.pressed.emit()
	scene._process(0)
	var after: Dictionary = scene.play_loop.duplicate(true)
	check(after["selected_unit_id"] == "enemy023_1" and not BattlePlayLoop.action_exhausted(after), "one exhausted action hands off to the immediate next player")
	scene._process(0.2)
	view.refresh(scene.play_loop, scene.map_config, true, true, 10)
	check(scene.play_loop == after and rewards.size() == 1 and deaths.size() == 1 and not actor.visible, "old receipt refresh neither resurrects the victim nor repeats a reward/turn")
	scene.queue_free()
	await process_frame


func counter_defeat() -> void:
	var scene := fixture()
	var player := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	player["hp"] = 1
	player["combat_profile"]["live_attack_damage"] = 1
	var enemy := BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["hp"] = 100
	enemy["max_hp"] = 100
	enemy["growth_profile"]["source"]["defense"] += 1000 - int(enemy["combat_profile"]["live_defense"])
	enemy["growth_profile"]["source"]["attack_back"] += 100 - int(enemy["combat_profile"]["attack_back"])
	enemy["growth_profile"]["source"]["attack_power"] += 1000 - int(enemy["combat_profile"]["live_attack_damage"])
	enemy.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(enemy,scene.play_loop["equipment_items"]),true)
	enemy["hp"] = 100;enemy["max_hp"] = 100
	attack(scene)
	var settled: Dictionary = scene.play_loop.duplicate(true)
	var view = scene.get_node("BattlePresentation")
	check(not settled["last_combat"]["counter"].is_empty() and settled["battle_outcome"] == BattleOutcome.DEFEAT_FALLEN, "real counterattack resolves terminal player death")
	scene._process(0)
	scene._process(view.attack_cue.duration)
	view.cutin._process(100)
	scene._process(0)
	check(view.cutin.busy() and not view.dialogue_active() and not view.battle_finished, "counter clip completes before any terminal aftermath")
	view.cutin._process(100)
	scene._process(0)
	check(view.aftermath.stage == "fade" and scene.actor_node_for_unit("leonard").visible, "script-owned Leonard death has no invented template line")
	check(death_sounds(scene, "leonard") == 1, "a death without last words sounds as its stretch starts (counterattack)")
	scene._process(view.aftermath.FADE_SECONDS / 2)
	check(scene.actor_node_for_unit("leonard").scale.y > 2.0, "a counterattack death (the player side, 0x443501..) runs the same stretch disposal")
	scene._process(1)
	scene._process(0)
	scene._process(2)
	scene._process(0)
	# The development fixture carries no winfail script, so no closing line precedes the
	# result (the first battle's 304 / 371 lines are asserted on battle_051 in
	# run_battle_scene_runtime_tests); the result follows the map death and earned rewards.
	check(not view.dialogue_active() and view.battle_finished, "terminal result follows map death and earned rewards")
	check(view.battle_finished and scene.play_loop == settled and not scene.ai_playback_active, "terminal result never advances a dead actor's queue")
	scene.queue_free()
	await process_frame


func multi_target() -> void:
	# Presentation contract fixture: two already-settled targets from one area
	# receipt, including a secondary victim. This is not a native spell claim.
	var scene := fixture()
	var view = scene.get_node("BattlePresentation")
	var secondary := BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_2")
	secondary["coord"] = BattlePlayLoop.unit(scene.play_loop, "leonard")["coord"] + Vector2i.RIGHT
	attack(scene)
	var receipt: Dictionary = scene.play_loop["last_combat"]
	var first := receipt.duplicate(true)
	first.erase("counter")
	var second := first.duplicate(true)
	second["defender_id"] = secondary["id"]
	receipt["affected_targets"] = [first, second]
	BattlePlayLoop.set_unit_hp(scene.play_loop, secondary["id"], 0)
	BattlePlayLoop.set_unit_defeated(scene.play_loop, secondary["id"], true)
	scene.apply_loop(scene.play_loop, "test")
	check(scene.actor_node_for_unit(secondary["id"]).visible, "secondary lethal target is retained before the first refresh")
	finish_cutin(scene)
	check(view.aftermath.retains(secondary["id"]), "secondary death stays queued while primary last words are visible")
	var disposed: Array = []
	view.aftermath.disposal_started.connect(func(unit): disposed.append(str(unit["id"])))
	check(disposed.is_empty() and death_sounds(scene, "enemy021_1") == 0, "no multi-target death sounds while the first last words are up")
	confirm(scene)
	check(disposed == ["enemy021_1"] and death_sounds(scene, "enemy021_1") == 1, "the first victim sounds as its own stretch starts")
	scene._process(1)
	scene._process(0)
	check(not scene.actor_node_for_unit("enemy021_1").visible and scene.actor_node_for_unit(secondary["id"]).visible and view.aftermath.dialogue_active(), "two victims with identical source text receive separate presentations")
	check(disposed == ["enemy021_1"], "the second victim's death sound waits for its own last words")
	confirm(scene)
	check(disposed == ["enemy021_1", secondary["id"]], "the second victim sounds as its own stretch starts")
	check(view.aftermath.stage == "fade", "the second victim's page closes into its own stretch")
	var settled: Dictionary = scene.play_loop.duplicate(true)
	view.aftermath.finish(scene)
	view.aftermath.finish(scene)
	view.refresh(scene.play_loop, scene.map_config, true)
	check(not view.combat_busy(scene.play_loop) and not view.dialogue_active() and not scene.actor_node_for_unit(secondary["id"]).visible, "explicit fast-forward clears every remaining victim and modal once")
	check(scene.play_loop == settled, "fast-forward cannot reapply HP/EXP or consume the turn")
	scene.queue_free()
	await process_frame


func terminal_victory() -> void:
	var scene := fixture()
	# Controlled post-switch fixture. The strike, final-enemy predicate and
	# outcome are live; this does not claim a complete six-round playthrough.
	scene.play_loop["objective_phase"] = "escape"
	scene.play_loop["win_statuses"] = [0, 1]
	for unit in scene.play_loop["units"]:
		if unit["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY and unit["id"] != "enemy021_1":
			unit["hp"] = 0
			unit["defeated"] = true
	attack(scene)
	var view = scene.get_node("BattlePresentation")
	check(scene.play_loop["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED, "last enemy kill enters the live victory rule")
	finish_cutin(scene)
	check(view.current_message_id() == expected_line(view.aftermath, "enemy021_1", "021") and not view.battle_finished, "last enemy's speech precedes victory")
	confirm(scene)
	scene._process(1)
	scene._process(0)
	check(view.aftermath.reward_label.visible and not view.battle_finished and not view.dialogue_active(), "victory cannot cover the final earned EXP")
	scene._process(2)
	scene._process(0)
	check(view.aftermath.reward_label.text == "$ 100" and not view.battle_finished, "final gold is visible before the victory story")
	scene._process(2)
	scene._process(0)
	check(not view.dialogue_active() and view.battle_finished, "the result follows the completed rewards (no script closing line in the development fixture)")
	scene.queue_free()
	await process_frame


## The final blow levels its striker (user decision 2026-09-24, as the original: 0x442720 phase 8
## opens the window in the attacker's completion, before the win scan): after the last words,
## EXP, $ and LEVEL UP floats the level-up window opens and the result page waits for it.
## Allocating commits the points on the won loop; the harness skip seam (hide) lets the result
## follow with the points left on the member for the carry.
func terminal_victory_level_up(skip: bool) -> void:
	var scene := fixture()
	scene.play_loop["objective_phase"] = "escape"
	scene.play_loop["win_statuses"] = [0, 1]
	for unit in scene.play_loop["units"]:
		if unit["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY and unit["id"] != "enemy021_1":
			unit["hp"] = 0
			unit["defeated"] = true
	BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["exp"] = 99
	attack(scene)
	var view = scene.get_node("BattlePresentation")
	var label := " (skip seam)" if skip else ""
	check(BattleOutcome.won(scene.play_loop) and int(BattlePlayLoop.unit(scene.play_loop, "leonard")["pending_stat_points"]) == 5, "the final blow wins and levels 雷歐納德" + label)
	finish_cutin(scene)
	confirm(scene)
	scene._process(1)
	scene._process(0)
	# 0x442720: EXP → $ → LEVEL UP (sfxLevelUp) → the window; the result waits for all of them.
	var shown: Array[String] = [str(view.aftermath.reward_label.text)]
	var level_up_sound := false
	for _step in range(3):
		scene._process(2)
		scene._process(0)
		if view.aftermath.busy():
			shown.append(str(view.aftermath.reward_label.text))
			if view.aftermath.reward_label.text == "LEVEL UP":
				level_up_sound = scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("level_up.wav")
		check(not scene.growth_panel.visible or not view.aftermath.busy(), "no window over a float" + label)
	check(shown.size() == 3 and shown[0].begins_with("EXP ") and shown[1].begins_with("$ ") and shown[2] == "LEVEL UP" and level_up_sound and not view.battle_finished, "the floats run EXP → $ → LEVEL UP with its sound, before the window, the result waits (%s)%s" % [str(shown), label])
	check(not view.aftermath.busy() and scene.growth_panel.visible and str(scene.growth_panel.source_unit["id"]) == "leonard", "the final blow's level-up window opens after the floats" + label)
	check(not view.battle_finished, "the battle end waits for the level-up window" + label)
	var before: Dictionary = BattlePlayLoop.unit(scene.play_loop, "leonard")
	if skip:
		scene.growth_panel.hide() # the harness skip seam; a player cannot close before OK
	else:
		for _point in range(int(before["pending_stat_points"])):
			scene.growth_panel.choices["con"]["plus"].pressed.emit()
		scene.growth_panel.confirm_button.pressed.emit()
	scene._process(0)
	var after: Dictionary = BattlePlayLoop.unit(scene.play_loop, "leonard")
	check(not scene.growth_panel.visible and view.battle_finished and BattleOutcome.won(scene.play_loop), "the victory result follows the closed window" + label)
	if skip:
		check(int(after["pending_stat_points"]) == 5 and int(BattlePlayLoop.CampaignCarryRules.capture(scene.play_loop)["units"]["leonard"]["pending_stat_points"]) == 5, "skipped points stay on the member and ride the carry")
		scene._process(0)
		check(not scene.growth_panel.visible and view.battle_finished, "a skipped window does not reopen over the result")
	else:
		check(int(after["pending_stat_points"]) == 0 and int(after["combat_profile"]["con"]) == int(before["combat_profile"]["con"]) + 5 and int(BattlePlayLoop.CampaignCarryRules.capture(scene.play_loop)["units"]["leonard"]["attributes"]["con"]) == int(after["combat_profile"]["con"]), "the points commit on the won loop and ride the carry")
	scene.queue_free()
	await process_frame


## A kill that drops loot and levels its striker (lane R6-P3; 0x442720 phases 0／2／4／6／8):
## KILL is not due (chain 1), EXP → $ → the get-item window → LEVEL UP with sfxLevelUp → the
## level-up window. The LEVEL UP float waits while the get-item window is open.
func kill_loot_level_up_order() -> void:
	var scene := fixture()
	var view = scene.get_node("BattlePresentation")
	var aftermath = view.aftermath
	BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["exp"] = 99
	BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")["inventory"] = [281, 0, 0, 0, 0, 0, 0, 0] # an important drop always drops
	var level_ups: Array = []
	aftermath.level_up_presented.connect(func(growth): level_ups.append(growth))
	attack(scene)
	check(BattlePlayLoop.loot_waiting(scene.play_loop) and int(BattlePlayLoop.unit(scene.play_loop, "leonard")["level"]) == 2, "the kill both drops loot and levels 雷歐納德")
	finish_cutin(scene)
	confirm(scene)
	var order: Array[String] = []
	var loot_seen_before_level_up := false
	for _frame in range(2400):
		var panel_open: bool = scene.settlement_controller.panel.visible
		if panel_open and not order.has("loot"):
			order.append("loot")
			check(aftermath.holding_for_loot() and level_ups.is_empty() and aftermath.reward_label.text != "LEVEL UP", "the LEVEL UP float waits behind the get-item window")
			loot_seen_before_level_up = true
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(BattlePlayLoop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		if aftermath.busy() and aftermath.reward_label.visible and (order.is_empty() or order.back() != aftermath.reward_label.text):
			order.append(str(aftermath.reward_label.text))
			if aftermath.reward_label.text == "LEVEL UP":
				check(scene.ui_audio.playing and scene.ui_audio.stream.resource_path.ends_with("level_up.wav") and level_ups.size() == 1, "sfxLevelUp starts with the LEVEL UP float")
		if scene.growth_panel.visible:
			order.append("window")
			break
		scene._process(1.0 / 60.0)
	check(order.size() == 5 and order[0].begins_with("EXP ") and order[1].begins_with("$ ") and order[2] == "loot" and order[3] == "LEVEL UP" and order[4] == "window" and loot_seen_before_level_up, "kill with loot and a level: EXP → $ → get-item → LEVEL UP → level-up window (%s)" % str(order))
	scene.queue_free()
	await process_frame


## A unit whose placed object installed obj_Data8 (live +0x14, unit `dead_message`) speaks
## that word instead of its PLAYERS row pair: the fixture's 021 (row pair 372／373) carrying
## level 34's villager word speaks 373 under 村民; carrying a −1 clear it fades without a line;
## carrying a word a script actSetDeadMessage wrote at run time (ids and the token's speaker
## id only, WinfailActions.write_dead_message) it speaks the level's text for that id under
## the speaker the id names.
func installed_dead_message() -> void:
	var thirty_four: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_034.json"))
	var villager: Dictionary = thirty_four["playable_units"].filter(func(row): return str(row["actor_id"]) == "062")[0]
	var twenty_four: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_024.json"))
	var cleared: Dictionary = twenty_four["playable_units"].filter(func(row): return str(row["actor_id"]) == "024")[0]
	var scripted := {"speaker": "", "speaker_id": "377", "messages": [{"id": "375"}]}
	for word in [villager["dead_message"], cleared["dead_message"], scripted]:
		var scene := fixture()
		BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")["dead_message"] = (word as Dictionary).duplicate(true)
		scene.apply_loop(scene.play_loop, "test")
		var view = scene.get_node("BattlePresentation")
		var tail = view.aftermath
		attack(scene)
		var settled: Dictionary = scene.play_loop.duplicate(true)
		finish_cutin(scene)
		var actor: Node2D = scene.actor_node_for_unit("enemy021_1")
		if (word["messages"] as Array).is_empty():
			check(not view.dialogue_active() and tail.stage == "fade" and actor.visible, "the −1 clear (level 24's 024) fades the victim without its row pair 374／375")
		elif word == scripted:
			check(view.dialogue_active() and view.current_message_id() == "375" and view.dialogue_view.speaker_label.text == "重裝兵：" and view.dialogue_view.body_label.text == "團長，抱歉我不行了........", "a run-time script word resolves its id 375 and speaker id 377 through the level's message texts")
			confirm(scene)
			check(tail.stage == "fade" and not view.dialogue_active(), "one confirmation releases the scripted line")
		else:
			check(view.dialogue_active() and view.current_message_id() == "373" and view.dialogue_view.speaker_label.text == "村民：" and actor.visible, "the installed word (level 34's villager) speaks 373 under its 稱號, not the row's 372")
			confirm(scene)
			check(tail.stage == "fade" and not view.dialogue_active(), "one confirmation releases the installed line")
		scene._process(tail.FADE_SECONDS)
		scene._process(0)
		check(not actor.visible and tail.reward_label.visible and tail.reward_label.text.contains("EXP"), "the reward follows the fade as for a row line")
		check(BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["defeated"] and scene.play_loop == settled, "the installed word never changes committed state")
		scene.queue_free()
		await process_frame


## A caster whose art row carries an imported m_shape lead (025 here) poses when the lead ends —
## the clip's `released`, where 0x402fd1 calls 0x4071e0 with the Cast_Star burst — not before.
func map_magic_lead_pose() -> void:
	var scene := fixture()
	var caster := BattlePlayLoop.unit_ref(scene.play_loop, "enemy026_1")
	var target := BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
	target["coord"] = caster["coord"] + Vector2i.RIGHT
	caster["mp"] = 100
	var id := "magic:magicFIRE:magicCode01"
	var receipt := BattleLoopCombat.resolve_skill(scene.play_loop, caster["id"], target["id"], id, BattlePlayLoop.skill_fields(scene.play_loop, id), caster["coord"], func(_n): return 0)
	check(not receipt.is_empty(), "the lead-pose fixture resolves a map spell")
	caster["actor_id"] = "025"
	scene.apply_loop(scene.play_loop, "test")
	var view = scene.get_node("BattlePresentation")
	scene._process(0)
	scene._process(view.attack_cue.duration)
	var node: Node2D = scene.actor_node_for_unit(caster["id"])
	check(view.cutin.busy() and not view.cutin.cast_lead(view.cutin.clips[0], "magic").is_empty(), "the 025 row carries a magic cast lead")
	check(not node.is_posing(), "the caster does not pose while its cast lead plays")
	var clip: Dictionary = view.cutin.clips[0]
	var steps := 0
	while view.cutin.busy() and not clip["release_emitted"] and steps < 2000:
		view.cutin._process(0.02)
		steps += 1
		if not clip["release_emitted"]:
			view.refresh(scene.play_loop, scene.map_config, true)
			if node.is_posing(): break
	# The loop breaks on a pose before the release; the pose itself comes with the release (0x402fd1).
	check(clip["release_emitted"], "no pose before the lead's release")
	view.refresh(scene.play_loop, scene.map_config, true)
	check(node.is_posing(), "the caster takes its use_magic pose as the lead ends")
	scene.queue_free()
	await process_frame


func map_magic() -> void:
	for key in ["fire", "wind"]:
		var scene := fixture()
		var caster := BattlePlayLoop.unit_ref(scene.play_loop, "enemy026_1")
		var target := BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
		target["hp"] = 1
		target["coord"] = caster["coord"] + Vector2i.RIGHT
		caster["mp"] = 100
		var id: String = "magic:magicAIR:magicCode01" if key == "wind" else "magic:magicFIRE:magicCode01"
		var receipt := BattleLoopCombat.resolve_skill(scene.play_loop, caster["id"], target["id"], id, BattlePlayLoop.skill_fields(scene.play_loop, id), caster["coord"], func(_n): return 0)
		check(not receipt.is_empty() and receipt["defender_hp_after"] == 0 and receipt.get("experience",{}).get("allocation")=="automatic" and receipt["experience"]["gained"]>0, "source AI magic commits its own automatic EXP, not player points: " + key)
		var settled: Dictionary = scene.play_loop.duplicate(true)
		scene.apply_loop(scene.play_loop, "test")
		var view = scene.get_node("BattlePresentation")
		finish_cutin(scene)
		# 026 has no m_shape lead: it poses after the 8 shadow calls, with the Cast_Star burst (0x403128).
		check(scene.actor_node_for_unit(caster["id"]).is_posing(), "the map caster without a lead takes its use_magic pose: " + key)
		check(view.magic_impact.busy() and not view.dialogue_active(), "map receiver bars and amount finish before death dialogue: " + key)
		view.magic_impact._process(view.magic_impact.total_seconds())
		scene._process(0)
		check(view.current_message_id() == expected_line(view.aftermath, target["id"], str(target["actor_id"])) and scene.actor_node_for_unit(target["id"]).visible, "map spell victim gets its own source last words: " + key)
		check(death_sounds(scene, target["id"]) == 0, "a map-spell death sound waits for the last words: " + key)
		confirm(scene)
		check(death_sounds(scene, target["id"]) == 1, "a map-spell death sounds as its stretch starts: " + key)
		scene._process(view.aftermath.FADE_SECONDS / 2)
		check(scene.actor_node_for_unit(target["id"]).scale.y > 2.0, "a map-spell death runs the same stretch disposal: " + key)
		scene._process(1)
		check(view.aftermath.busy() and not view.aftermath.reward_label.visible and not scene.actor_node_for_unit(target["id"]).visible, "AI map spell fades the victim before its actual EXP: " + key)
		scene._process(0)
		# 0x442720 phase 0: the camera first glides to the recipient (the caster, off-centre here).
		check(view.aftermath.stage == "focus" and not view.aftermath.reward_label.visible, "the camera glides to the recipient before its EXP: " + key)
		scene._process(view.aftermath.focus_seconds)
		scene._process(0)
		check(view.aftermath.reward_label.visible and view.aftermath.reward_label.text=="EXP %d" % receipt["experience"]["gained"], "NPC reward displays the exact committed amount: "+key)
		scene._process(view.aftermath.REWARD_SECONDS)
		# The AI killer's own kill gold floats its $ after the EXP (0x44287b joins both branches).
		scene._process(0)
		scene._process(view.aftermath.REWARD_SECONDS)
		check(not view.aftermath.busy(), "NPC map reward completes once without an allocation dialog: "+key)
		check(scene.play_loop == settled, "map magic aftermath never modifies committed rules: " + key)
		scene.queue_free()
		await process_frame


# ---- run_combat_aftermath_tests.gd ----
## The level-up window offer (BattleSceneMenus.offer_pending_growth／open_growth,
## BattleSceneRuntime.growth_offered_levels, BattleLoopRewards.allocate_growth): the window
## opens for any player member whose current level has not been offered — after the
## EXP／LEVEL UP floats, before the next hand-off (0x442720 phase 8) — regardless of who was
## offered before, whether the member is the current actor, or whose turn it is. Level 3
## (雷歐納德／緹娜／琥, 琥 acts first) is the three-member formation.
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const BattleForceWin = preload("res://tests/support/BattleForceWin.gd")
const SCENARIO := "res://content/battles/battle_003.json"
func run_growth_offer() -> void:
	# Reproducible formation and rolls (the headless loop-seed seam the autoplay sweep uses).
	OS.set_environment("HSL_RNG_SEED", "1")
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	await _test_second_member_at_lower_level()
	await _test_status_reaches_any_member()
	await _test_enemy_turn_counter_level_up()
	await _test_enemy_turn_counter_level_up(true)
	for skip in [false, true]:
		await _test_terminal_victory_offers_before_story(skip)
	await _test_terminal_defeat_offers_nothing()
	_test_checkpoint_offers()
func _start() -> Node:
	# Every case boots from the seeded global stream, not from where the previous case's
	# opening and enemy turns left the process stream (the formation must be the same).
	GlobalRandomStream.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = SCENARIO
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame
	return scene


func _close(scene: Node) -> void:
	scene.queue_free()
	await process_frame


## Levels the member up once in place (as a settled EXP award would) and mirrors the loop.
func _level_up(scene: Node, id: String) -> void:
	var unit: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, id)
	unit["exp"] = BattlePlayLoop.ProgressionRules.exp_to_next(int(unit["level"])) - 1
	unit.merge(BattlePlayLoop.ProgressionRules.resolve_experience(unit, 1, scene.play_loop["equipment_items"]), true)
	scene.apply_loop(scene.play_loop, "test")


func _state(scene: Node) -> String:
	var view = scene.get_node("BattlePresentation")
	return "inter=%s sel=%s busy=%s dlg=%s loot=%s motion=%s modal=%s script=%s" % [scene.interaction_state, scene.selected_unit_id, view.combat_busy(scene.play_loop), view.dialogue_active(), BattlePlayLoop.loot_waiting(scene.play_loop), scene.has_actor_motion(), scene.modal_open(), scene.ScriptPresentation.pending(scene)]


func _offered_to(scene: Node) -> String:
	return str(scene.growth_panel.source_unit.get("id", "")) if scene.growth_panel.visible else ""


func _spend_all(scene: Node) -> void:
	var points := int(scene.growth_panel.source_unit["pending_stat_points"])
	for i in range(points):
		scene.growth_panel.choices["con"]["plus"].pressed.emit()
	scene.growth_panel.confirm_button.pressed.emit()


## The recorded bug: 雷歐納德 8→9 was offered, then 琥 7→8 never was (one battle-wide level).
func _test_second_member_at_lower_level() -> void:
	var scene = await _start()
	scene.set_process(false)
	check(scene.selected_unit_id == "hu" and scene.interaction_state == Interaction.ACTION_MENU, "level 3 opens on 琥's action menu")
	_level_up(scene, "hu")
	_level_up(scene, "hu") # 琥 now stands two levels above 緹娜's next level
	scene._process(0.0)
	check(_offered_to(scene) == "hu", "the acting member's level-up opens the window")
	scene.growth_panel.hide() # harness skip seam: points stay, the same level is not offered again
	scene._process(0.0)
	check(not scene.growth_panel.visible, "a skipped level is not offered every frame")
	var hu_level := int(BattlePlayLoop.unit(scene.play_loop, "hu")["level"])
	_level_up(scene, "tina")
	check(int(BattlePlayLoop.unit(scene.play_loop, "tina")["level"]) < hu_level, "緹娜 levels up to a level below the one already offered to 琥")
	scene._process(0.0)
	check(_offered_to(scene) == "tina", "another member's lower level-up still opens its own window (per-member offer)")
	_spend_all(scene)
	check(not scene.growth_panel.visible and int(BattlePlayLoop.unit(scene.play_loop, "tina")["pending_stat_points"]) == 0, "a non-current member's allocation commits through allocate_growth")
	check(scene.selected_unit_id == "hu" and scene.interaction_state == Interaction.ACTION_MENU, "allocating for 緹娜 leaves 琥's turn untouched")
	scene._process(0.0)
	check(not scene.growth_panel.visible, "琥's skipped level is not reoffered")
	await _close(scene)


## Status 成長點 reopens points left unallocated (old save／harness skip) for any member, not only the current actor.
func _test_status_reaches_any_member() -> void:
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "leonard")
	scene._process(0.0)
	check(_offered_to(scene) == "leonard", "雷歐納德's level-up is offered while 琥 acts " + _state(scene))
	scene.growth_panel.hide()
	scene.status_panel.show_unit(BattlePlayLoop.unit(scene.play_loop, "leonard"))
	check(scene.status_panel.growth_button.visible, "雷歐納德's status page shows his unspent points")
	scene.status_panel.growth_button.pressed.emit()
	check(_offered_to(scene) == "leonard" and not scene.status_panel.visible, "成長點 reopens the window for the inspected non-current member")
	_spend_all(scene)
	check(int(BattlePlayLoop.unit(scene.play_loop, "leonard")["pending_stat_points"]) == 0, "the reopened window commits 雷歐納德's points")
	await _close(scene)


## Enemy turn: a foe strikes 緹娜, her counter kills it and levels her; the window opens
## after the aftermath floats and holds the next AI step until it closes. `final_blow`: the
## foe is the last enemy, so the foe's completed-action scan wins the battle inside the enemy
## step — the window still opens first and the victory cutscene／result follow it.
func _test_enemy_turn_counter_level_up(final_blow: bool = false) -> void:
	var scene = await _start()
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	if final_blow:
		for unit in loop["units"]:
			if unit["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY and unit["id"] != "actor028_2" and BattlePlayLoop.Presence.living(unit):
				BattlePlayLoop.set_unit_defeated(loop, unit["id"], true)
	var tina: Dictionary = BattlePlayLoop.unit_ref(loop, "tina")
	var foe: Dictionary = BattlePlayLoop.unit_ref(loop, "actor028_2")
	for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if foe["coord"] == tina["coord"] + step: break
		var at: Vector2i = tina["coord"] + step
		if BattlePlayLoop.unit_id_at_coord(loop, at) == "" and BattlePlayLoop.TraversalRules.placement_error(foe.merged({"coord": at}, true), loop["units"], loop["tiles"], loop["map_size"]) == "":
			foe["coord"] = at
			break
	check(BattlePlayLoop.Footprint.overlaps(foe, BattlePlayLoop.attack_cells(loop, "tina")), "028_2 stands in 緹娜's counter reach")
	tina["exp"] = BattlePlayLoop.ProgressionRules.exp_to_next(int(tina["level"])) - 1
	tina["hit_bonus_accum"] = 1000
	foe["hp"] = 1
	loop["interaction"] = Interaction.AI_RESOLVING
	loop["selected_unit_id"] = ""
	var level_before := int(tina["level"])
	# The counter gate (CoreCombatRules.attack_back_triggered) rolls; take the first seed
	# whose exchange draws a lethal counter.
	var strike := {}
	var fought := {}
	for seed in range(1, 200):
		fought = loop.duplicate(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		strike = BattleLoopCombat.resolve_exchange(fought, "actor028_2", "tina", rng)
		if not strike.get("counter", {}).is_empty() and int(BattlePlayLoop.unit(fought, "actor028_2")["hp"]) == 0: break
	loop = fought
	if final_blow:
		# The foe's action completes in its own death sequence (0x407510 → win scan).
		loop = BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(loop, true))
		check(BattleOutcome.won(loop), "the counter on the last foe wins inside the enemy step")
	check(not strike.is_empty() and not strike.get("counter", {}).is_empty(), "the foe's strike draws 緹娜's counter")
	check(int(BattlePlayLoop.unit(loop, "tina")["level"]) > level_before and int(BattlePlayLoop.unit(loop, "actor028_2")["hp"]) == 0, "the counter kills the foe and levels 緹娜")
	scene.apply_loop(loop, "test")
	scene.resume_turn_presentation()
	check(scene.ai_playback_active or final_blow, "the enemy turn is playing back")
	var saw_float := false
	var saw_level_up := false
	var opened_after_float := false
	var queue_while_open: Variant = null
	for frame in range(1800):
		var view = scene.get_node("BattlePresentation")
		var aftermath = view.aftermath
		if aftermath.stage == "experience": saw_float = true
		if aftermath.stage == "level_up" and saw_float: saw_level_up = true
		if view.dialogue_active(): view.advance_dialogue()
		if BattlePlayLoop.loot_waiting(scene.play_loop):
			# The get-item window (0x442720 phase 4) precedes the level-up window; 稍後.
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(BattlePlayLoop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		scene._process(1.0 / 60.0)
		if scene.growth_panel.visible:
			opened_after_float = saw_float and not aftermath.busy()
			queue_while_open = scene.play_loop["turn_queue"].duplicate(true)
			break
		await process_frame
	check(_offered_to(scene) == "tina", "the counter's level-up opens 緹娜's window during the enemy turn")
	check(opened_after_float, "the window follows the EXP／LEVEL UP float (0x442720 phase 8 after phase 6)")
	check(saw_level_up, "the counter's level-up shows its own LEVEL UP float after the EXP float (0x442720 phase 6)")
	for i in range(30):
		scene._process(1.0 / 60.0)
	check(scene.growth_panel.visible and scene.play_loop["turn_queue"] == queue_while_open, "no AI step runs while the window is open")
	if final_blow:
		var view = scene.get_node("BattlePresentation")
		check(not view.battle_finished and not scene.opening_coordinator.active, "the enemy-turn final blow holds the victory cutscene and result behind the window")
	_spend_all(scene)
	check(not scene.growth_panel.visible and int(BattlePlayLoop.unit(scene.play_loop, "tina")["pending_stat_points"]) == 0, "緹娜's points commit during the enemy turn")
	if final_blow:
		var view = scene.get_node("BattlePresentation")
		var coordinator = scene.opening_coordinator
		coordinator.walk_pixels_per_second = 6400.0
		coordinator.delay_token_seconds = 0.001
		coordinator.default_step_seconds = 0.005
		scene.set_process(true)
		for _frame in range(1200):
			if view.battle_finished: break
			if coordinator.active and str(coordinator.summary().get("current_event_kind", "")) in BattleForceWin.CLICK_THROUGH_KINDS: coordinator.handle_input(BattleForceWin.click())
			elif view.dialogue_active(): view.advance_dialogue()
			await process_frame
		check(view.battle_finished and BattleOutcome.won(scene.play_loop) and not scene.ai_playback_active, "the victory result follows the enemy-turn window (%s)" % _state(scene))
	await _close(scene)


## The final blow of a won battle (user decision 2026-09-24, as the original: 0x442720 phase 8
## runs in the attacker's completion, before the action ends and the win scan 0x44ee20 runs):
## level 3's clear fires win_0, whose closing cutscene and the result page wait for the level-up
## window of a member other than the actor. Allocating commits on the won loop; the harness skip
## seam (hide) lets the victory script and the result follow, the points stay for the carry and
## the next battle's first quiet moment offers them.
func _test_terminal_victory_offers_before_story(skip: bool) -> void:
	var label := " (skip seam)" if skip else ""
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "tina")
	var loop: Dictionary = scene.play_loop.duplicate(true)
	for unit in loop["units"]:
		if unit["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY and BattlePlayLoop.Presence.living(unit):
			BattlePlayLoop.set_unit_defeated(loop, unit["id"], true)
	loop = BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(loop))
	check(BattleOutcome.won(loop) and scene.ScriptPresentation.timeline(scene, "win_0").get("playable_event_count", 0) > 0, "level 3's clear wins through win_0's closing cutscene" + label)
	scene.apply_loop(loop, "test")
	scene.mirror_interaction()
	var coordinator = scene.opening_coordinator
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	var view = scene.get_node("BattlePresentation")
	scene.set_process(true)
	for _frame in range(120):
		if scene.growth_panel.visible or coordinator.active or view.battle_finished: break
		await process_frame
	check(_offered_to(scene) == "tina", "the final blow's window opens for 緹娜 (%s)%s" % [_state(scene), label])
	check(not coordinator.active and not view.dialogue_active() and not view.battle_finished, "the victory cutscene and the result page wait for the window" + label)
	for _frame in range(10): await process_frame
	check(scene.growth_panel.visible and not coordinator.active and not view.battle_finished, "the window holds the victory flow while open" + label)
	if skip:
		scene.growth_panel.hide() # the harness skip seam; a player cannot close before OK
	else:
		_spend_all(scene)
	var tina: Dictionary = BattlePlayLoop.unit(scene.play_loop, "tina")
	check(not scene.growth_panel.visible and int(tina["pending_stat_points"]) == (5 if skip else 0), "the window closes; the points %s%s" % ["stay" if skip else "commit on the won loop", label])
	var cutscene_played := false
	for _frame in range(1200):
		if view.battle_finished: break
		if coordinator.active:
			cutscene_played = true
			if str(coordinator.summary().get("current_event_kind", "")) in BattleForceWin.CLICK_THROUGH_KINDS: coordinator.handle_input(BattleForceWin.click())
		elif view.dialogue_active():
			view.advance_dialogue()
		await process_frame
	check(cutscene_played and view.battle_finished and BattleOutcome.won(scene.play_loop), "the victory cutscene, then the result page, follow the window (%s)%s" % [_state(scene), label])
	check(not scene.growth_panel.visible, "the window does not reopen over the result" + label)
	var carried := int(BattlePlayLoop.CampaignCarryRules.capture(scene.play_loop)["units"]["tina"]["pending_stat_points"])
	check(carried == (5 if skip else 0), "the carry keeps exactly the unspent points" + label)
	await _close(scene)
	if not skip: return
	var next = await _start()
	next.set_process(false)
	# The carried member (CampaignCarryRules keeps pending_stat_points) is not the first actor.
	BattlePlayLoop.unit_ref(next.play_loop, "tina")["pending_stat_points"] = carried
	next.apply_loop(next.play_loop, "test")
	next._process(0.0)
	check(next.selected_unit_id == "hu" and _offered_to(next) == "tina", "carried points open the member's window at the next battle's first control")
	await _close(next)


## A lost battle offers no window (provisional, the conservative reading: a defeat restarts the
## battle, so points won on its last exchange cannot be kept) and the loop rejects allocation.
func _test_terminal_defeat_offers_nothing() -> void:
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "hu")
	var loop: Dictionary = scene.play_loop.duplicate(true)
	BattlePlayLoop.set_unit_defeated(loop, "leonard", true)
	loop = BattlePlayLoop.resolve_outcome(loop)
	check(BattleOutcome.lost(loop), "雷歐納德's fall loses level 3")
	scene.apply_loop(loop, "test")
	scene.mirror_interaction()
	var view = scene.get_node("BattlePresentation")
	scene.set_process(true)
	for _frame in range(120):
		if scene.growth_panel.visible or view.battle_finished: break
		if view.dialogue_active(): view.advance_dialogue()
		await process_frame
	check(not scene.growth_panel.visible and view.battle_finished and not scene.menus.terminal_growth_pending(), "a defeat shows its result without a level-up window (%s)" % _state(scene))
	check(BattlePlayLoop.allocate_growth(scene.play_loop, "hu", {"con": 1}) == scene.play_loop, "a lost loop rejects allocation")
	await _close(scene)


func _test_checkpoint_offers() -> void:
	var loop: Dictionary = BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file(SCENARIO))
	var legacy := BattleCheckpoint.growth_offered_levels({"growth_notified_level": 9}, loop)
	check(legacy.size() == loop["units"].size() and int(legacy["hu"]) == int(BattlePlayLoop.unit(loop, "hu")["level"]), "a pre-per-member save restores every member as offered at its current level")
	var saved := BattleCheckpoint.growth_offered_levels({"growth_offered_levels": {"hu": 5}}, loop)
	check(saved == {"hu": 5}, "a per-member save restores its own offers")
