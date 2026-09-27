extends SceneTree
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const LevelUpStars = preload("res://game/battle/scene/LevelUpStars.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
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
	var player := BattlePlayLoop._unit(scene.play_loop, "leonard")
	player["live_speed"] = 100
	player["stamina"] = 60
	var next := BattlePlayLoop._unit(scene.play_loop, "enemy023_1")
	next["growth_profile"]["source"]["speed"] += 99 - int(next["live_speed"])
	next.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(next,scene.play_loop["equipment_items"]),true)
	next["player_commandable"] = true
	next["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	var enemy := BattlePlayLoop._unit(scene.play_loop, "enemy021_1")
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


func confirm(scene: Node) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.pressed = true
	scene._input(event)


func run() -> void:
	for command in ["attack", "special"]:
		for fps in [30, 144]:
			await lethal_case(command, fps)
	await nonlethal_and_miss()
	await counter_defeat()
	await map_magic()
	await map_magic_lead_pose()
	await item_use_pose()
	await multi_target()
	await terminal_victory()
	for skip in [false, true]:
		await terminal_victory_level_up(skip)
	await kill_loot_level_up_order()
	await installed_dead_message()
	dead_message_choice()
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
	BattlePlayLoop._unit(scene.play_loop, "leonard")["exp"] = 99
	scene._process(0)
	check(scene.actor_node_for_unit("leonard").highlight_kind() == "actor" and scene.actor_node_for_unit("enemy021_1").highlight_kind() == "", "the unit choosing its command carries the actor highlight")
	scene.menus.choose_command(command)
	if command == "special": scene.menus._choose_magic("special:magicOTHER:magicCode01")
	scene.hovered_unit_id = "enemy021_1"
	scene.hovered_grid_cell = BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["coord"]
	scene._process(0)
	scene._process(0)
	check(scene.interaction_state == "attack_select" and scene.actor_node_for_unit("enemy021_1").highlight_kind() == "target", "the legal target under the target cursor carries the target highlight (%s, %s)" % [scene.interaction_state, scene.actor_node_for_unit("enemy021_1").highlight_kind()])
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
	check(actor.highlight_kind() == "" and scene.actor_node_for_unit("leonard").highlight_kind() == "", "no target／actor highlight while the last words are up")
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
	check(is_equal_approx(tail.FADE_SECONDS, 16 * 0.016) and absf(actor.scale.y - 3.0) < 0.3 and actor.scale.x == 1.0 and absf(actor.modulate.a - 0.5) < 0.1 and actor.material is CanvasItemMaterial and (actor.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "the death disposal stretches the actor upward while it fades, additively (scale %s alpha %.2f)" % [str(actor.scale), actor.modulate.a])
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


func nonlethal_and_miss() -> void:
	for missed in [false, true]:
		var scene := fixture()
		var view = scene.get_node("BattlePresentation")
		var enemy := BattlePlayLoop._unit(scene.play_loop, "enemy021_1")
		enemy["hp"] = 100
		enemy["max_hp"] = 100
		enemy["no_attack"] = true
		if missed:
			BattlePlayLoop._unit(scene.play_loop, "leonard")["combat_profile"]["live_hit_ratio"] = 0
			enemy["combat_profile"]["avoid_hit_ratio"] = 100
		attack(scene, "attack", missed)
		finish_cutin(scene)
		check(not view.dialogue_active() and scene.actor_node_for_unit("enemy021_1").visible, "nonlethal exchange has no death speech or fade")
		check(view.aftermath.reward_label.visible == not missed, "only an earned EXP receipt creates map reward feedback")
		if not missed: scene._process(view.aftermath.REWARD_SECONDS)
		check(scene.selected_unit_id == "enemy023_1", "nonlethal/miss completion still reaches the next player once")
		scene.queue_free()
		await process_frame


func counter_defeat() -> void:
	var scene := fixture()
	var player := BattlePlayLoop._unit(scene.play_loop, "leonard")
	player["hp"] = 1
	player["combat_profile"]["live_attack_damage"] = 1
	var enemy := BattlePlayLoop._unit(scene.play_loop, "enemy021_1")
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
	var secondary := BattlePlayLoop._unit(scene.play_loop, "enemy021_2")
	secondary["coord"] = BattlePlayLoop.unit(scene.play_loop, "leonard")["coord"] + Vector2i.RIGHT
	attack(scene)
	var receipt: Dictionary = scene.play_loop["last_combat"]
	var first := receipt.duplicate(true)
	first.erase("counter")
	var second := first.duplicate(true)
	second["defender_id"] = secondary["id"]
	receipt["affected_targets"] = [first, second]
	BattlePlayLoop._set_unit_hp(scene.play_loop, secondary["id"], 0)
	BattlePlayLoop._set_unit_defeated(scene.play_loop, secondary["id"], true)
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
	BattlePlayLoop._unit(scene.play_loop, "leonard")["exp"] = 99
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
	BattlePlayLoop._unit(scene.play_loop, "leonard")["exp"] = 99
	BattlePlayLoop._unit(scene.play_loop, "enemy021_1")["inventory"] = [281, 0, 0, 0, 0, 0, 0, 0] # an important drop always drops
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
		BattlePlayLoop._unit(scene.play_loop, "enemy021_1")["dead_message"] = (word as Dictionary).duplicate(true)
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
	var caster := BattlePlayLoop._unit(scene.play_loop, "enemy026_1")
	var target := BattlePlayLoop._unit(scene.play_loop, "enemy023_1")
	target["coord"] = caster["coord"] + Vector2i.RIGHT
	caster["mp"] = 100
	var id := "magic:magicFIRE:magicCode01"
	var receipt := BattleLoopCombat._resolve_skill(scene.play_loop, caster["id"], target["id"], id, BattlePlayLoop.skill_fields(scene.play_loop, id), caster["coord"], func(_n): return 0)
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
	check(clip["release_emitted"] and not node.is_posing(), "no pose before the lead's release")
	view.refresh(scene.play_loop, scene.map_config, true)
	check(node.is_posing(), "the caster takes its use_magic pose as the lead ends")
	scene.queue_free()
	await process_frame


## Item use poses the user: 0x4449a7 (player item-target confirmation) and 0x440366／0x4404c7
## (AI items) call 0x4071e0 before 0x409e40 applies the item.
func item_use_pose() -> void:
	var scene := fixture()
	var view = scene.get_node("BattlePresentation")
	var node: Node2D = scene.actor_node_for_unit("leonard")
	check(not node.is_posing(), "no pose before the item")
	check(view.show_item_use({"sequence": 900, "actor_id": "leonard", "target_id": "leonard", "restored_hp": 12}, node.position), "item feedback starts")
	check(node.is_posing() and sprite_path(node).ends_with("/001-M0001.png"), "the item user takes its use_magic pose (%s)" % sprite_path(node))
	view.finish_item_feedback()
	scene.queue_free()
	await process_frame


func map_magic() -> void:
	for key in ["fire", "wind"]:
		var scene := fixture()
		var caster := BattlePlayLoop._unit(scene.play_loop, "enemy026_1")
		var target := BattlePlayLoop._unit(scene.play_loop, "enemy023_1")
		target["hp"] = 1
		target["coord"] = caster["coord"] + Vector2i.RIGHT
		caster["mp"] = 100
		var id: String = "magic:magicAIR:magicCode01" if key == "wind" else "magic:magicFIRE:magicCode01"
		var receipt := BattleLoopCombat._resolve_skill(scene.play_loop, caster["id"], target["id"], id, BattlePlayLoop.skill_fields(scene.play_loop, id), caster["coord"], func(_n): return 0)
		check(not receipt.is_empty() and receipt["defender_hp_after"] == 0 and receipt.get("experience",{}).get("allocation")=="automatic" and receipt["experience"]["gained"]>0, "source AI magic commits its own automatic EXP, not player points: " + key)
		var settled: Dictionary = scene.play_loop.duplicate(true)
		scene.apply_loop(scene.play_loop, "test")
		var view = scene.get_node("BattlePresentation")
		finish_cutin(scene)
		# 026 has no m_shape lead: it poses as the clip starts, beside the Cast_Star ring (R7-POSE).
		check(scene.actor_node_for_unit(caster["id"]).is_posing(), "the map caster without a lead takes its use_magic pose: " + key)
		check(view.magic_impact.busy() and not view.dialogue_active(), "map receiver bars and amount finish before death dialogue: " + key)
		view.magic_impact._process(view.magic_impact.VITALS_SECONDS + view.magic_impact.float_seconds())
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
		check(not view.aftermath.busy(), "NPC map reward completes once without an allocation dialog: "+key)
		check(scene.play_loop == settled, "map magic aftermath never modifies committed rules: " + key)
		scene.queue_free()
		await process_frame
