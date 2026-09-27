extends RefCounted

## Fixture-free autoplay driver: plays a booted formal battle to its natural outcome
## with no clearing, protection or status override. Player-commandable units act through
## BattlePlayLoop's public command entry points only (choose_command / move_unit_to /
## attack_target / finish_exhausted_action / finish_rewards), choosing by a minimal greedy
## policy (strike a reachable foe, else approach the nearest foe, else wait); every AI unit
## takes its ordinary step_ai_turn. Rules run headless on the loop dictionary for speed;
## script cutscenes fired by the winfail interpreter and the final result page are the
## scene's own transitions, so the driver hands the loop back to the scene for those
## frames and takes it again afterwards. Nothing here is evidence about original balance:
## a win or a loss only says the rules reached an outcome; a dead_end names a rule path
## that never did. An opt-in commander (tests/support/AutoplayBrain.gd, `brain` argument)
## replaces only the player-turn policy; with no brain the greedy policy below runs unchanged.

const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const Brain = preload("res://tests/support/AutoplayBrain.gd")
const Runtime = preload("res://game/battle/scene/BattleSceneRuntime.gd")
const Progression = preload("res://game/sim/ProgressionRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

## Harness diagnostic (never product, never results.json): HSL_AUTOPLAY_STAT_SCALE=1.5
## multiplies the controlled units' attributes at first control (apply_stat_scale) so a run
## can measure how far the commander is from a party a competent player would field.
const STAT_SCALE_ENV := "HSL_AUTOPLAY_STAT_SCALE"
const SCALED_ATTRIBUTES := ["str", "dex", "mind", "con"]

## Seed the booted scene gives its loop RNG streams and the process's global stream
## (BattleSceneRuntime.LOOP_SEED_ENV, read only headless) when the caller has not chosen one;
## the driver's own greedy draws use play_battle's `seed`. Set before the scene boots (and
## reset the global stream, GlobalRandomStream.reset_session) so two runs replay the same battle.
const DEFAULT_LOOP_SEED := 1

## Round limit: an undecided battle past this many rounds is a dead_end, whatever the
## clock (autoplay is CPU-bound; a fixed-fps frame and a real frame do the same work).
const DEFAULT_ROUND_LIMIT := 60
## Rounds without any exchange while both sides live before the driver calls it a stalemate
## (not while an escape objective is live: see play_battle).
const STALEMATE_ROUNDS := 10
## Rounds the undecided battle keeps running after the last player-side unit fell.
const PARTY_WIPED_ROUNDS := 3
## Rule steps inside one round before the driver declares the round stalled.
const STEP_LIMIT_PER_ROUND := 4000
## Frame cap for each scene phase (cutscene playback, result page).
const FRAME_LIMIT := 9000

const OUTCOME_WIN := "win"
## Result-row `battle_outcome` of a battle the campaign hand-off ended before the loop decided
## (event-only terminal, WINFAIL073/078/900): the autoplayer's own victory reason, not a loop outcome.
const EVENT_HANDOFF_OUTCOME := {"result": BattleOutcome.VICTORY, "reason": "event_handoff"}
const OUTCOME_FAIL := "fail"
const OUTCOME_DEAD_END := "dead_end"

## dead_end categories (content/generated/hsl/development/autoplay/results.json `reason`):
## no_legal_action — a player unit's menu offers no command that ends its action;
## party_wiped_no_defeat — no player-side unit (controlled or friendly) lives for
##   PARTY_WIPED_ROUNDS rounds yet no fail status holds; outcome_never_armed — no enemy lives yet no win status holds;
## stalemate_no_contact — both sides live but no exchange for STALEMATE_ROUNDS rounds
##   (nobody can reach anybody, or the greedy policy idles); round_limit — still fighting
##   at DEFAULT_ROUND_LIMIT; stalled — one round exceeds STEP_LIMIT_PER_ROUND rule steps or
##   a step makes no progress; exception — scenario_error or an unexpected interaction.
const REASON_NO_LEGAL_ACTION := "no_legal_action"
const REASON_PARTY_WIPED := "party_wiped_no_defeat"
const REASON_OUTCOME_NEVER_ARMED := "outcome_never_armed"
const REASON_STALEMATE := "stalemate_no_contact"
const REASON_ROUND_LIMIT := "round_limit"
const REASON_STALLED := "stalled"
const REASON_EXCEPTION := "exception"


## Exports BattleSceneRuntime.LOOP_SEED_ENV = DEFAULT_LOOP_SEED unless the environment already
## names a seed (printed once as `AUTOPLAY_RNG_SEED … source=harness_default` when it sets
## it); returns the seed in force. Call before booting the scene, so a direct run of a suite
## seeds the damage, reward and global streams as a gate run does.
static func ensure_loop_seed() -> int:
	if not OS.get_environment(Runtime.LOOP_SEED_ENV).is_valid_int():
		OS.set_environment(Runtime.LOOP_SEED_ENV, str(DEFAULT_LOOP_SEED))
		print("AUTOPLAY_RNG_SEED seed=%d source=harness_default" % DEFAULT_LOOP_SEED)
	return int(OS.get_environment(Runtime.LOOP_SEED_ENV))


static func stat_scale_from_environment() -> float:
	var value := OS.get_environment(STAT_SCALE_ENV)
	return float(value) if value.is_valid_float() and float(value) > 0.0 else 1.0


## Multiplies every player_controlled unit's SCALED_ATTRIBUTES (combat_profile) by `scale`,
## except the ids in `already_scaled` (a chapter walk carries scaled attributes from battle to
## battle, so each unit is scaled once), re-derives its live stats through
## ProgressionRules.refresh_growth_stats (the rules' own level-up path) and fills its HP.
## Returns {loop, scaled: [ids]}; scale 1.0 returns the loop as is.
static func apply_stat_scale(loop: Dictionary, scale: float, already_scaled: Array = []) -> Dictionary:
	if is_equal_approx(scale, 1.0) or not bool(loop.get("scenario_ok", false)):
		return {"loop": loop, "scaled": []}
	var next := Loop.copy(loop)
	var scaled: Array = []
	var units: Array = next["units"]
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var id := str(unit.get("id", ""))
		if str(unit.get("battle_actor_role", "")) != Loop.ROLE_PLAYER or already_scaled.has(id) or not unit.has("growth_profile"):
			continue
		var profile: Dictionary = unit["combat_profile"]
		for key in SCALED_ATTRIBUTES:
			if profile.has(key):
				profile[key] = int(round(float(profile[key]) * scale))
		var refreshed := Progression.refresh_growth_stats(unit, next["equipment_items"])
		refreshed["hp"] = int(refreshed["max_hp"])
		units[index] = refreshed
		scaled.append(id)
	return {"loop": next, "scaled": scaled}


## Plays the opening to first control, like tests/support/BattleForceWin.gd play_opening
## (dialogue clicked through, walks accelerated, the level fixture's `opening_select_option`
## row taken at a choice — formal 900's second row enters the battle branch), then the first battle's own scene timeline
## confirmed page by page until BattleSceneRuntime enters its first-control state. An
## event-only battle (73) hands the campaign off inside its opening instead; that counts
## as reaching the end of the opening, not as a failure.
static func reach_first_control(tree: SceneTree, scene: Node, label: String, assert_cb: Callable) -> void:
	var coordinator = scene.opening_coordinator
	if coordinator != null:
		coordinator.walk_pixels_per_second = 6400.0
	var select_option := ForceWin.opening_select_option(scene)
	for _frame in range(FRAME_LIMIT):
		if CampaignProgress.has_pending():
			return
		if coordinator == null or not coordinator.active:
			break
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		elif not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(select_option)
		elif str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(ForceWin.click())
		await tree.process_frame
	assert_cb.call(coordinator == null or not coordinator.active, "%s: the opening reaches first control" % label)
	for _frame in range(FRAME_LIMIT):
		if str(scene.interaction_state) != "opening_timeline":
			break
		if str(RuntimeReadback.opening_timeline_summary(scene).get("current_event_kind", "")) == "dialogue_message_id":
			scene.advance_opening_timeline("confirm")
		await tree.process_frame
	assert_cb.call(str(scene.interaction_state) != "opening_timeline", "%s: the scene timeline reaches first control" % label)


## Plays `scene` (already at first control) to its outcome. Returns
## {outcome, battle_outcome (BattleOutcome structure, {} when none, EVENT_HANDOFF_OUTCOME for a hand-off), rounds, fallen (player_controlled units down at the end), seconds, reason, unit, round, detail, actions, result_page (the scene reached BattlePresentation.battle_finished or a hand-off; historical key name)}.
## `brain` (AutoplayBrain.create) commands the player turns instead of the greedy policy;
## the result then also carries `brain` statistics.
static func play_battle(tree: SceneTree, scene: Node, round_limit: int = DEFAULT_ROUND_LIMIT, seed: int = 1, brain: Dictionary = {}) -> Dictionary:
	var started := Time.get_ticks_msec()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var actions := {"attack": 0, "move_then_attack": 0, "move": 0, "wait": 0, "offense_finished": 0, "ai_steps": 0, "loot_deferred": 0, "scene_phases": 0}
	if not brain.is_empty():
		for action in Brain.ACTIONS:
			if not actions.has(action):
				actions[action] = 0
	var result := {"outcome": OUTCOME_DEAD_END, "battle_outcome": {}, "rounds": 0, "seconds": 0.0, "reason": "", "unit": "", "round": 0, "detail": "", "actions": actions, "result_page": false}
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	var steps_this_round := 0
	var last_round := -1
	var last_contact_round := 1
	var party_wiped_since := -1
	while true:
		var verdict := _verdict(loop)
		if verdict != "":
			result["outcome"] = verdict
			break
		if not bool(loop.get("scenario_ok", false)):
			_dead_end(result, loop, REASON_EXCEPTION, str(loop.get("scenario_error", "scenario_error")))
			break
		var round_number := int(loop.get("turn", 1))
		if round_number != last_round:
			last_round = round_number
			steps_this_round = 0
		if int((loop.get("last_combat", {}) as Dictionary).get("sequence", 0)) != int(result.get("_contact_sequence", 0)):
			result["_contact_sequence"] = int(loop["last_combat"]["sequence"])
			last_contact_round = round_number
		var enemies_alive := not _living_foes_of_players(loop).is_empty()
		var party_alive := not _living_players(loop).is_empty()
		if party_alive:
			party_wiped_since = -1
		elif party_wiped_since < 0:
			party_wiped_since = round_number
		# A live escape objective is exempt: a good escape is exactly rounds without an exchange
		# (level 53, M2: every +25% run that outran the pursuers ended here as a dead_end at round 11).
		var escaping := str(loop.get("objective_phase", "")) == "escape" and not (loop.get("escape_zone", []) as Array).is_empty()
		var stalemate := party_alive and enemies_alive and not escaping and round_number - last_contact_round >= STALEMATE_ROUNDS
		if not party_alive and round_number - party_wiped_since >= PARTY_WIPED_ROUNDS:
			_dead_end(result, loop, REASON_PARTY_WIPED, "interaction=%s %s" % [str(loop.get("interaction", "")), _roster_detail(loop)])
			break
		if stalemate or round_number > round_limit:
			var reason := REASON_STALEMATE if stalemate else (REASON_OUTCOME_NEVER_ARMED if not enemies_alive else REASON_ROUND_LIMIT)
			_dead_end(result, loop, reason, "interaction=%s last_contact_round=%d %s" % [str(loop.get("interaction", "")), last_contact_round, _roster_detail(loop)])
			break
		steps_this_round += 1
		if steps_this_round > STEP_LIMIT_PER_ROUND:
			_dead_end(result, loop, REASON_STALLED, "interaction=%s current=%s" % [str(loop.get("interaction", "")), str(Loop.summary(loop).get("current_actor_id", ""))])
			break
		if _unconsumed_firing(scene, loop) or _event_handoff_fired(loop):
			actions["scene_phases"] += 1
			loop = await _play_scene_phase(tree, scene, loop, false)
			continue
		if Loop.loot_waiting(loop):
			# The commander first takes the healing / curing items a player would bag (AutoplayBrain.claim_supplies).
			if not brain.is_empty():
				var supplied := Brain.claim_supplies(loop)
				if not Loop.same_state(supplied, loop):
					actions["loot_deferred"] += 1
					loop = supplied
					continue
			# The collection panel's "later": keep the pending items, close the settlement.
			var settlement: Dictionary = loop["settlement"]
			var deferred := Loop.finish_rewards(loop, int(settlement["sequence"]), int(settlement["revision"]), false, true)
			if Loop.same_state(deferred, loop):
				_dead_end(result, loop, REASON_STALLED, "loot settlement cannot be deferred")
				break
			actions["loot_deferred"] += 1
			loop = deferred
			continue
		match str(loop.get("interaction", "")):
			"action_menu":
				var step := Brain.take_player_action(brain, loop, rng) if not brain.is_empty() else _take_player_action(loop, rng)
				if str(step["action"]) == "":
					_dead_end(result, loop, REASON_NO_LEGAL_ACTION, "commands=%s" % str((loop.get("command_menu", {}) as Dictionary).get("commands", [])))
					break
				actions[step["action"]] += 1
				if OS.get_environment("HSL_AUTOPLAY_DEBUG_AI") != "":
					print("STEP_DBG turn=%d actor=%s action=%s %s" % [int(loop.get("turn", 0)), str(loop.get("selected_unit_id", "")), str(step["action"]), _step_diff(loop, step["loop"])])
				loop = step["loop"]
			"ai_resolving":
				# The product path: the AI draws from the loop's global stream (global_rng).
				var stepped := Loop.step_ai_turn(loop)
				# Developer trace of every AI step (actor, kind, target, hero HP, last exchange).
				if OS.get_environment("HSL_AUTOPLAY_DEBUG_AI") != "":
					var act: Dictionary = stepped.get("last_ai_action", {})
					var hero_dbg := Loop.unit(stepped, str(stepped.get("player_unit_id", "")))
					var lc: Dictionary = stepped.get("last_combat", {})
					print("AI_DBG turn=%d actor=%s kind=%s from=%s to=%s target=%s hero_hp=%d combat=%s->%s dmg=%s counter=%s" % [int(stepped.get("turn", 0)), str(act.get("actor_id", "")), str(act.get("kind", "")), str(act.get("from", "")), str(act.get("to", "")), str(act.get("target_id", act.get("defender_id", ""))), int(hero_dbg.get("hp", -1)), str(lc.get("attacker_id", "")), str(lc.get("defender_id", "")), str(lc.get("damage", lc.get("actual_damage", ""))), str((lc.get("counter", {}) as Dictionary).get("damage", ""))])
				if OS.get_environment("HSL_AUTOPLAY_DEBUG_AI") != "":
					print("STEP_DBG turn=%d actor=%s action=ai %s" % [int(loop.get("turn", 0)), str((stepped.get("last_ai_action", {}) as Dictionary).get("actor_id", "")), _step_diff(loop, stepped)])
				if Loop.same_state(stepped, loop):
					_dead_end(result, loop, REASON_STALLED, "step_ai_turn made no progress for %s" % str(Loop.summary(loop).get("current_actor_id", "")))
					break
				actions["ai_steps"] += 1
				loop = stepped
			"battle_result":
				# Outcome recorded without a verdict string: leave the classification to _verdict on the next pass.
				if not BattleOutcome.decided(loop):
					_dead_end(result, loop, REASON_EXCEPTION, "battle_result without battle_outcome")
					break
			_:
				_dead_end(result, loop, REASON_EXCEPTION, "interaction=%s" % str(loop.get("interaction", "")))
				break
	result.erase("_contact_sequence")
	result["battle_outcome"] = BattleOutcome.of(loop)
	if not BattleOutcome.decided(loop) and CampaignProgress.has_pending():
		result["battle_outcome"] = EVENT_HANDOFF_OUTCOME.duplicate()
	result["rounds"] = int(loop.get("turn", 1))
	result["fallen"] = loop.get("units", []).filter(func(unit): return str(unit.get("battle_actor_role", "")) == Loop.ROLE_PLAYER and not Loop.Presence.living(unit)).size()
	# A decided battle still owes the player its closing presentation or campaign hand-off.
	if str(result["outcome"]) != OUTCOME_DEAD_END:
		loop = await _play_scene_phase(tree, scene, loop, true)
		result["result_page"] = _presentation(scene).battle_finished or CampaignProgress.has_pending()
	else:
		scene.apply_loop(loop, "test")
		scene.set_process(true)
	result["seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	if not brain.is_empty():
		result["brain"] = Brain.stats(brain)
	return result


## Developer trace (HSL_AUTOPLAY_DEBUG_AI): every unit whose cell or HP one step changed,
## `id@x,y->x,y hp a->b`.
static func _step_diff(before: Dictionary, after: Dictionary) -> String:
	var parts: Array = []
	for unit in after.get("units", []):
		var old := Loop.unit(before, str(unit["id"]))
		var moved: bool = not old.is_empty() and old.get("coord") != unit.get("coord")
		var hurt: bool = old.is_empty() or int(old.get("hp", 0)) != int(unit.get("hp", 0))
		if not moved and not hurt:
			continue
		var text := str(unit["id"])
		if moved:
			text += "@%d,%d->%d,%d" % [old["coord"].x, old["coord"].y, unit["coord"].x, unit["coord"].y]
		if hurt:
			text += " hp %d->%d" % [int(old.get("hp", 0)), int(unit.get("hp", 0))]
		parts.append(text)
	return "; ".join(parts)


## One report line per battle: `AUTOPLAY level=51 outcome=win rounds=9 seconds=3.2`, with
## `reason=… unit=… round=N` appended for a dead_end.
static func format_line(level: String, result: Dictionary) -> String:
	var line := "AUTOPLAY level=%s outcome=%s rounds=%d fallen=%d seconds=%.1f" % [level, str(result["outcome"]), int(result["rounds"]), int(result.get("fallen", 0)), float(result["seconds"])]
	if not (result["battle_outcome"] as Dictionary).is_empty():
		line += " battle_outcome=%s" % BattleOutcome.describe(result["battle_outcome"])
	if str(result["outcome"]) == OUTCOME_DEAD_END:
		line += " reason=%s unit=%s round=%d detail=%s" % [str(result["reason"]), str(result["unit"]), int(result["round"]), str(result["detail"])]
	else:
		line += " result_page=%s" % str(result["result_page"])
	return line


static func _verdict(loop: Dictionary) -> String:
	var outcome := BattleOutcome.of(loop)
	if BattleOutcome.is_victory(outcome):
		return OUTCOME_WIN
	if BattleOutcome.is_defeat(outcome):
		return OUTCOME_FAIL
	if outcome.is_empty():
		# An event-only terminal (WINFAIL073/078/900) ends the battle by campaign hand-off;
		# the product would leave the scene here, whatever the coordinator still shows.
		if CampaignProgress.has_pending():
			return OUTCOME_WIN
		return ""
	return ""


static func _dead_end(result: Dictionary, loop: Dictionary, reason: String, detail: String) -> void:
	result["outcome"] = OUTCOME_DEAD_END
	result["reason"] = reason
	result["unit"] = str(Loop.summary(loop).get("current_actor_id", ""))
	result["round"] = int(loop.get("turn", 1))
	result["detail"] = detail


## Living roster at a dead_end, for the report: `role id@(x,y) hp/max mp=N` per unit.
static func _roster_detail(loop: Dictionary) -> String:
	var rows: Array = []
	for unit in loop.get("units", []):
		if not Loop.Presence.living(unit):
			continue
		var coord: Vector2i = unit.get("coord", Vector2i.ZERO)
		rows.append("%s %s@(%d,%d) hp=%d/%d mp=%d" % [str(unit.get("battle_actor_role", "")).trim_suffix("_ai").trim_suffix("_controlled"), str(unit["id"]), coord.x, coord.y, int(unit.get("hp", 0)), int(unit.get("max_hp", 0)), int(unit.get("move_point", 0))])
	var fallen: Array = []
	for unit in loop.get("units", []):
		if Loop.Presence.living(unit) or str(unit.get("battle_actor_role", "")) != Loop.ROLE_PLAYER:
			continue
		fallen.append("%s hp=%d defeated=%s departed=%s" % [str(unit["id"]), int(unit.get("hp", 0)), str(unit.get("defeated", false)), str(unit.get("departed", false))])
	var unresolved: Array = (loop.get("winfail_runtime", {}) as Dictionary).get("unresolved_tokens", []).map(func(record): return str((record as Dictionary).get("token", "")))
	return "living=[%s] fallen_players=[%s] win_statuses=%s fail_statuses=%s event_statuses=%s unresolved_tokens=%s" % ["; ".join(rows), "; ".join(fallen), str(loop.get("win_statuses", [])), str(loop.get("fail_statuses", [])), str(loop.get("event_statuses", [])), str(unresolved)]


## True while the scene has not yet consumed every status the interpreter fired: the scene
## alone replays a fired status (cutscene, inlined presentation, or nothing to play) and
## spawns the actors that status created, so the loop goes back to it before the next rule step.
static func _unconsumed_firing(scene: Node, loop: Dictionary) -> bool:
	var fired: Array = (loop.get("winfail_runtime", {}) as Dictionary).get("fired", [])
	return fired.size() > int(scene.script_cutscene_consumed)


## True when the interpreter fired the event-only hand-off status of an undecided battle;
## only the scene's cutscene path (BattleSceneRuntime.maybe_start_script_cutscene) may end it.
static func _event_handoff_fired(loop: Dictionary) -> bool:
	var status := str(loop.get("next_level_event_status", ""))
	if status == "" or BattleOutcome.decided(loop):
		return false
	for entry in (loop.get("winfail_runtime", {}) as Dictionary).get("fired", []):
		if str((entry as Dictionary).get("key", "")) == status:
			return true
	return false


## Hands the loop to the scene: script cutscenes replay (dialogue clicked through, the first
## choice row taken — formal 900's second row enters the battle branch like the sweep), story
## dialogue advances, loot panels defer, modal panels close. `to_result` keeps the frames going
## until the result page or campaign hand-off shows. Returns the loop the scene settled on.
static func _play_scene_phase(tree: SceneTree, scene: Node, loop: Dictionary, to_result: bool) -> Dictionary:
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var presentation = _presentation(scene)
	var select_option := ForceWin.opening_select_option(scene)
	var idle_frames := 0
	for _frame in range(FRAME_LIMIT):
		var coordinator = scene.opening_coordinator
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		elif coordinator != null and coordinator.active:
			idle_frames = 0
			if not (coordinator.summary().get("select_options", []) as Array).is_empty():
				coordinator.choose_select_option(select_option)
			elif str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
				coordinator.handle_input(ForceWin.click())
		elif presentation.dialogue_active():
			presentation.advance_dialogue()
		elif Loop.loot_waiting(scene.play_loop):
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(Loop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		elif CampaignProgress.has_pending() or presentation.battle_finished:
			break
		elif scene.growth_panel.visible:
			scene.growth_panel.hide()
		elif not to_result and not _unconsumed_firing(scene, scene.play_loop) and not _event_handoff_fired(scene.play_loop):
			# Every firing consumed; let motion and cues settle before taking the loop back.
			if scene.has_actor_motion() or presentation.combat_busy(scene.play_loop):
				idle_frames = 0
			else:
				idle_frames += 1
				if idle_frames > 2:
					break
		await tree.process_frame
	scene.set_process(false)
	return scene.play_loop


## Greedy player turn through the public command entry points. Returns {loop, action};
## action "" means no command made progress (the caller records no_legal_action).
static func _take_player_action(loop: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var id := str(loop.get("selected_unit_id", ""))
	if Loop.action_exhausted(loop):
		# An offense whose completion waited on loot collection ends the action now.
		return {"loop": Loop.finish_exhausted_action(loop), "action": "offense_finished"}
	var next := loop
	var moved := false
	if Loop.command_available(next, "attack"):
		var struck := _try_attack(next, id, rng)
		if not struck.is_empty():
			return {"loop": struck, "action": "attack"}
	if Loop.command_available(next, "move"):
		var destination: Variant = _destination(next, id)
		if destination is Vector2i:
			var moving := Loop.move_unit_to(Loop.choose_command(next, "move"), destination)
			if bool(moving.get("moved_this_action", false)):
				next = moving
				moved = true
				if Loop.command_available(next, "attack"):
					var struck := _try_attack(next, id, rng)
					if not struck.is_empty():
						return {"loop": struck, "action": "move_then_attack"}
			else:
				next = Loop.cancel_interaction(moving)
	var waited := Loop.choose_command(next, "wait")
	if Loop.same_state(waited, next):
		return {"loop": next, "action": ""}
	return {"loop": waited, "action": "move" if moved else "wait"}


## Strikes the weakest foe the selected unit can hit from where it stands; {} when none.
static func _try_attack(loop: Dictionary, id: String, _rng: RandomNumberGenerator) -> Dictionary:
	var actor := Loop.unit(loop, id)
	var cells: Array = Loop.attack_cells(loop, id)
	var target := ""
	var best_hp := 0
	var best_distance := 0
	for foe in _living_foes(loop, actor):
		if Loop.Footprint.contact(foe, cells) == null:
			continue
		var hp := int(foe.get("hp", 0))
		var distance := Loop.Footprint.distance(actor, foe)
		if target == "" or hp < best_hp or (hp == best_hp and distance < best_distance):
			target = str(foe["id"])
			best_hp = hp
			best_distance = distance
	if target == "":
		return {}
	# Settlement draws from the loop's damage stream (DamageRandomStream), as the product does.
	var struck := Loop.attack_target(Loop.choose_command(loop, "attack"), target)
	if BattleOutcome.decided(struck):
		return struck
	if not bool(struck.get("attacked_this_action", false)):
		return {}
	if Loop.loot_waiting(struck):
		# Drops or steals open the collection first; the caller defers them, then the
		# next player pass ends the exhausted action.
		return struck
	return Loop.finish_exhausted_action(struck)


## Movement destination: a reachable cell from which the weapon touches a foe (cheapest
## path, weakest foe), else the reachable cell nearest to the nearest foe; null when staying
## put is as good as any reachable cell. The flat pattern only proposes cells: a cell counts
## when the weapon's real reach from it (_weapon_cells_from — the cells _try_attack strikes
## through after the move) touches that foe, so a wall between never draws the unit there.
static func _destination(loop: Dictionary, id: String) -> Variant:
	var actor := Loop.unit(loop, id)
	var origin: Vector2i = actor["coord"]
	var cells: Array = Loop.movement_cells(loop, id)
	if cells.is_empty():
		return null
	var foes := _living_foes(loop, actor)
	if foes.is_empty():
		return null
	var reachable := {}
	for cell in cells:
		reachable[cell] = true
	var pattern := Loop.weapon_pattern(loop, actor)
	if not bool(actor.get("no_attack", false)) and bool(pattern.get("ok", false)):
		var strike_cell: Variant = null
		var best_cost := 0
		var best_hp := 0
		var reach := {}
		for foe in foes:
			for point in Loop.Footprint.cells(foe):
				for offset in pattern["offsets"]:
					var cell: Vector2i = point - Vector2i(int(offset[0]), int(offset[1]))
					if cell == origin or not reachable.has(cell):
						continue
					if not reach.has(cell):
						reach[cell] = _weapon_cells_from(loop, actor, pattern, cell)
					if Loop.Footprint.contact(foe, reach[cell]) == null:
						continue
					var cost := Loop.movement_path(loop, id, cell).size()
					var hp := int(foe.get("hp", 0))
					if strike_cell == null or cost < best_cost or (cost == best_cost and hp < best_hp):
						strike_cell = cell
						best_cost = cost
						best_hp = hp
		if strike_cell != null:
			return strike_cell
	var nearest: Variant = null
	var best_distance := _nearest_foe_distance(actor, origin, foes)
	for cell in cells:
		var distance := _nearest_foe_distance(actor, cell, foes)
		if distance < best_distance:
			nearest = cell
			best_distance = distance
	return nearest


## The weapon cells `actor` covers once standing on `cell`: BattlePlayLoop.weapon_cells (the
## original 0x40f8b0 flood over the map words) with the actor moved there, as attack_cells
## reads them after move_unit_to.
static func _weapon_cells_from(loop: Dictionary, actor: Dictionary, pattern: Dictionary, cell: Vector2i) -> Array:
	var moved := actor.duplicate()
	moved["coord"] = cell
	var probe := loop.duplicate()
	probe["units"] = loop["units"].map(func(unit): return moved if unit.get("id") == actor["id"] else unit)
	return Loop.weapon_cells(probe, moved, pattern)


static func _nearest_foe_distance(actor: Dictionary, origin: Vector2i, foes: Array) -> int:
	var best := -1
	for foe in foes:
		var distance := Loop.Footprint.distance(actor, foe, origin)
		if best < 0 or distance < best:
			best = distance
	return best


static func _living_foes(loop: Dictionary, actor: Dictionary) -> Array:
	var player_side := str(actor.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]
	var out: Array = []
	for unit in loop.get("units", []):
		if not Loop.Presence.living(unit) or str(unit.get("id", "")) == str(actor.get("id", "")):
			continue
		var unit_player_side := str(unit.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY]
		if unit_player_side != player_side:
			out.append(unit)
	return out


## Living player-side units (controlled or friendly AI): while one stands, the field can still change.
static func _living_players(loop: Dictionary) -> Array:
	return loop.get("units", []).filter(func(unit): return Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) in [Loop.ROLE_PLAYER, Loop.ROLE_FRIENDLY])


static func _living_foes_of_players(loop: Dictionary) -> Array:
	return loop.get("units", []).filter(func(unit): return Loop.Presence.living(unit) and str(unit.get("battle_actor_role", "")) == Loop.ROLE_ENEMY)


static func _presentation(scene: Node) -> Node:
	return scene.get_node("BattlePresentation")
