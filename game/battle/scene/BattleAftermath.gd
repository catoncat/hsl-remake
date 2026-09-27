extends Node
const CombatSequenceRules = preload("res://game/sim/CombatSequenceRules.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
## Read-only, sequence-scoped presentation after the complete combat exchange.
## Jobs contain receipt snapshots; no HP, EXP, inventory or turn is committed here.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/actor_hit_poses/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   layout: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   layout: runtime-measured docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##     (recording 337.95 KILL 3, 338.37 EXP, 338.97 $, 339.59 LEVEL UP)
##   strings: resource-derived content/generated/hsl/combat/aftermath.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_field_coverage.md
##   strings: resource-derived content/imported/hsl/chapter01/battle051/message_text_evidence.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: static-derived docs/evidence_packets/runtime_observations/dialogue_death/README.md
##   strings: remake-invented
##     (the roll is a hash of exchange sequence and victim instead of the original global PRNG: no combat RNG spent, a
##     reload speaks the same line)
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_death_disposal.md
##   timing: provisional
##     (draw mode 0x2c000000 read as additive, alpha = level／16; one $ float per action with its recipient — the
##     original keeps a second total 0x4c2978 for the counter)
##   audio: resource-derived content/imported/hsl/chapter01/actor_audio.json
##   audio: resource-derived content/imported/hsl/shared/actor_audio.json
##   audio: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   audio: static-derived docs/evidence_packets/static_reverse/original_death_disposal.md
signal experience_presented(growth: Dictionary)
## Emitted when a LEVEL UP float appears (0x4084e0 kind 6 plays sfxLevelUp 0x191 there).
signal level_up_presented(growth: Dictionary)
## Emitted once per defeated unit as its disposal (the upward stretch) starts — after its
## last words close, straight away when it has none (dead branch sub-state 0: 0x409700 plays
## the template's death sound as the stretch begins, 0x43eff9／0x443510). `unit` is the
## PlayLoop unit (the presentation binds the death sound by its job-up target row).
signal disposal_started(unit: Dictionary)

const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
## The native disposal of a fallen actor (enemy process 0x43ede0's dead branch 0x43eff9..0x43f0e6,
## the player process's 0x443501..0x443602 — the same steps): after its last words the actor
## switches to draw mode 0x2c000000 at zoom 1.0 and draw level 16, then each tick its vertical
## zoom grows 0x4000 (+0.25) and its level drops 1; at level 0 it is hidden. It stretches up from
## its foot anchor to 5× its height while it fades — the "soul rising" the player remembers.
const DEATH_TICKS := 16
const DEATH_STRETCH_PER_TICK := 0.25
const FADE_SECONDS := OriginalTick.TICK_SECONDS * DEATH_TICKS
## 0x2c000000 carries the additive draw bits (0x04000000／0x08000000 — the 0x46b6b1 table's
## saturating-add kinds) with the level: read as an additive blend at alpha level／16 (provisional:
## this mode's pixel routine is not read).
var death_blend := CanvasItemMaterial.new()
## The fallen actor's SHAPEDEF hit pose (NNN-P), drawn from its death entry through the last
## words and the stretch: 0x446c40(actor, facing, 6, 2) — state 6 is the record's offset-0 `hit`
## shape, one frame (static-derived; content/imported/hsl/shared/actor_hit_poses).
const HIT_POSES_PATH := "res://content/imported/hsl/shared/actor_hit_poses/manifest.json"
var hit_poses: Dictionary = {}
## Reward floats live the defProcShowNumber 46 ticks (BattleRewardFloater draws the level fade);
## the next reward phase starts when a float releases its waiter at tick 32, the earlier float
## fading on beside it.
const REWARD_SECONDS := Timing.SHOW_NUMBER_SECONDS
const REWARD_RELEASE_SECONDS := OriginalTick.TICK_SECONDS * Timing.SHOW_NUMBER_RELEASE_TICKS
## Spawn points above the object (0x442720 pushes y − 0x30; the dead branch y − 0x18).
const REWARD_LIFT := 48.0
const KILL_LIFT := 24.0
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
const LevelUpStars = preload("res://game/battle/scene/LevelUpStars.gd")
var source: Dictionary
var dialogue: Control
var ui: CanvasLayer
## The float of the current reward stage (hidden between stages); `text` names what it shows.
var reward_label: Node2D
## Released floats still fading, and KILL floats over fallen victims: {node, coord, lift}.
var trailing: Array[Dictionary] = []
var jobs: Array[Dictionary] = []
var sequence := 0
var cursor := 0
var stage := "idle"
var elapsed := 0.0
## The running reward-recipient glide's seconds (stage "focus") and the glides started so far.
var focus_seconds := 0.0
var focus_count := 0


func _ready() -> void:
	death_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	source = ContentPaths.read_json("res://content/generated/hsl/combat/aftermath.json")
	assert(source.get("schema") == "hsl_combat_aftermath.v1", "Missing combat aftermath source data")
	var poses: Variant = ContentPaths.read_json(HIT_POSES_PATH)
	assert(typeof(poses) == TYPE_DICTIONARY and (poses as Dictionary).get("schema") == "hsl_actor_hit_poses.v1", "Missing actor hit poses")
	hit_poses = (poses as Dictionary)["poses"]
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	reward_label = _new_float()


func _new_float() -> Node2D:
	var node: Node2D = BattleRewardFloater.new()
	node.name = "MapExperience"
	ui.add_child(node)
	return node


static func defeated_ids(receipt: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	var strikes := CombatSequenceRules.outcomes(receipt)
	for strike in strikes:
		if int(strike.get("defender_hp_before", 0)) > 0 and int(strike["defender_hp_after"]) <= 0:
			var id := str(strike["defender_id"])
			if not ids.has(id): ids.append(id)
	return ids


## Every PLAYERS row is declared in aftermath.json (`messages: []` = the row's own silence).
## A defeated actor outside the table is a data error: it is reported once and still falls
## silently, so the exchange completes and the result page stays reachable (no busy() lock).
func death_template(actor_id: String) -> Dictionary:
	if source["actors"].has(actor_id):
		return source["actors"][actor_id]
	push_error("Missing death-message template (aftermath.json declares every PLAYERS row): " + actor_id)
	return {"speaker_id": "", "speaker": "", "messages": []}


## `message_texts` is the level's RESOURCE id → text table (the presentation's dialogue
## manifest): a `dead_message` written at run time by a script actSetDeadMessage
## (WinfailActions) carries ids and possibly a speaker id only and is resolved here.
func prepare(receipt: Dictionary, units: Array, message_texts: Dictionary = {}) -> void:
	var incoming := int(receipt["sequence"])
	if incoming <= sequence: return
	assert(not busy(), "A new exchange cannot replace unfinished aftermath")
	sequence = incoming
	jobs.clear()
	cursor = 0
	elapsed = 0.0
	# Built locally and published at the end: an aborted build must not leave a half queue
	# behind whose stage never advances (busy() forever, no result page).
	var queued: Array[Dictionary] = []
	for id in defeated_ids(receipt):
		var unit := _unit(units, id)
		var actor_id := str(unit["actor_id"])
		# The unit's own installed death word (obj_Data8 → live +0x14, unit `dead_message`;
		# an empty list is the −1 clear) wins over its PLAYERS row's pair.
		var definition: Dictionary = unit["dead_message"] if unit.has("dead_message") else death_template(actor_id)
		var message: Dictionary = choose_dead_message(definition["messages"], dead_message_roll(incoming, id)).duplicate(true)
		var speaker := str(definition.get("speaker", ""))
		if not message.is_empty() and not message.has("text"):
			if not message_texts.has(str(message["id"])):
				# Every script message id of the level is in its message texts; a miss is a data error.
				push_error("Death line %s of %s is not in the level's message texts" % [str(message["id"]), id])
				message = {}
			else:
				message["text"] = str(message_texts[str(message["id"])])
				if speaker == "":
					speaker = str(message_texts.get(str(definition.get("speaker_id", "")), death_template(actor_id)["speaker"]))
		# The victim's dead branch floats its killer's chain (0x43f07c..0x43f0aa): the counter's
		# chain for the attacker a counter killed, the action's for every other victim.
		var counter: Dictionary = receipt.get("counter", {})
		var killing: Dictionary = counter if id == str(receipt["attacker_id"]) and not counter.is_empty() else receipt
		queued.append({"kind": "death", "unit_id": id, "actor_id": actor_id, "unit": unit,
			"speaker": speaker, "message": message, "kill_count": int(killing.get("kill_chain", 0))})
	var strikes: Array = [receipt]
	if not receipt.get("counter", {}).is_empty(): strikes.append(receipt["counter"])
	var rewards: Dictionary = receipt.get("rewards", {})
	# 0x442720 case 2 floats *0x4c2c84 once for the action: the drop gold plus what a StealGold
	# special (竊殺／銀之手) took — 0x40b556..0x40b574 adds the take there on both caster sides.
	# The float pushes the paid amount (0x44288a), after the gold_x2 doubling (0x442825).
	var gold := int(rewards.get("gold", 0))
	for effect in receipt.get("gold_effects", []):
		gold += int(effect.get("paid", effect["amount"]))
	var gold_owner := ""
	if gold > 0:
		gold_owner = str(rewards["kills"][0]["attacker_id"]) if int(rewards.get("gold", 0)) > 0 else str(receipt["attacker_id"])
	# 0x442720 runs once per recipient — the attacker (0x4447d8／0x4416bc), then the countering
	# target (0x44483c／0x441724): EXP (phase 0), its $ (phase 2), [get-item window, phase 4],
	# one LEVEL UP whatever the levels gained (phase 6). The recording's 501.48 EXP → 502.05
	# LEVEL UP → 502.70 second EXP shows the grouping.
	for strike in strikes:
		var growth: Dictionary = strike.get("experience", {})
		var recipient := str(strike["attacker_id"])
		if int(growth.get("gained", 0)) <= 0 and gold_owner != recipient: continue
		var unit := _unit(units, recipient)
		var first_reward := queued.size()
		if int(growth.get("gained", 0)) > 0:
			queued.append({"kind": "experience", "coord": unit["coord"], "growth": growth.duplicate(true)})
			for learned in growth.get("learning", []):
				queued.append({"kind": "learning", "coord": unit["coord"], "text": str(learned)})
		if gold_owner == recipient:
			queued.append({"kind": "gold", "coord": unit["coord"], "gold": gold})
			gold_owner = ""
		if int(growth.get("gained", 0)) > 0 and int(growth.get("level_after", 0)) > int(growth.get("level_before", 0)):
			queued.append({"kind": "level_up", "unit_id": recipient, "coord": unit["coord"], "growth": growth.duplicate(true)})
		# 0x442720 phase 0: the camera glides to the recipient before its first float.
		queued[first_reward]["focus"] = true
	if gold_owner != "":
		queued.append({"kind": "gold", "coord": _unit(units, gold_owner)["coord"], "gold": gold, "focus": true})
	jobs = queued
	stage = "queued" if not jobs.is_empty() else "idle"


## The death branch's line choice (0x43ef91..0x43efcb enemy, 0x4434b2.. player — static-derived):
## a zero word is silence, a zero half is replaced by the other half, and `0x458c10() & 1`
## (the original global PRNG) picks the second listed half when odd, else the first. `messages`
## lists the halves in that order (one entry when both are the same, none for silence).
static func choose_dead_message(messages: Array, roll: int) -> Dictionary:
	if messages.is_empty(): return {}
	return messages[1 if (roll & 1) == 1 and messages.size() > 1 else 0]


## The roll replacing 0x458c10 (remake-invented): a deterministic hash of the exchange sequence
## and the victim, so the choice spends no combat RNG (autoplay results and every later roll are
## unchanged) and a reloaded exchange speaks the same line. Replaceable by a PlayLoop RNG draw
## if the original's shared stream is ever modelled.
static func dead_message_roll(exchange_sequence: int, unit_id: String) -> int:
	return ("%d:%s" % [exchange_sequence, unit_id]).hash()


func busy() -> bool:
	return cursor < jobs.size()


## The LEVEL UP stage waits for the get-item window (0x442720 phase 4 precedes phase 6): while
## loot is pending the aftermath holds here and the settlement may open its window.
func holding_for_loot() -> bool:
	return busy() and stage == "loot_hold"


func dialogue_active() -> bool:
	return busy() and stage == "dialogue"


func current_message_id() -> String:
	return str(jobs[cursor]["message"]["id"]) if dialogue_active() else ""


func retains(unit_id: String) -> bool:
	for index in range(cursor, jobs.size()):
		if jobs[index]["kind"] == "death" and jobs[index]["unit_id"] == unit_id: return true
	return false


func advance(delta: float, runtime: Node) -> void:
	_advance_trailing(delta, runtime)
	if not busy(): return
	var job := jobs[cursor]
	if stage == "focus":
		elapsed += maxf(0.0, delta)
		var controller = _camera(runtime)
		if controller != null and controller.is_scrolling():
			if elapsed < focus_seconds: return
			controller.finish_scroll()
		stage = "queued"
		return
	if stage == "queued":
		elapsed = 0.0
		if bool(job.get("focus", false)) and not bool(job.get("focused", false)):
			job["focused"] = true
			if _begin_focus(runtime, job["coord"]): return
		if job["kind"] == "death":
			var actor: Node2D = runtime.actor_node_for_unit(job["unit_id"])
			assert(actor != null, "Missing defeated map actor")
			actor.modulate = Color.WHITE
			show_hit_pose(actor)
			if not job["message"].is_empty():
				stage = "dialogue"
				dialogue.show_message("combat:%d:%d" % [sequence, cursor], job["speaker"], job["message"]["text"], job["actor_id"])
			else:
				_begin_disposal()
		elif job["kind"] == "experience":
			stage = "experience"
			var growth: Dictionary = job["growth"]
			reward_label.present("experience", int(growth["gained"]))
			_position_reward(runtime, job["coord"])
			experience_presented.emit(growth.duplicate(true))
		elif job["kind"] == "level_up":
			stage = "loot_hold"
			if not _loot_waiting(runtime): _present_level_up(runtime, job)
		else:
			stage = str(job["kind"])
			if stage == "learning":
				reward_label.present("learning", 0, str(job["text"]).replace("（尚未可用）", "\n（尚未可用）"))
			else:
				reward_label.present("gold", int(job["gold"]))
			_position_reward(runtime, job["coord"])
		return # Every new stage gets a visible frame, including after a long delta.
	if stage == "dialogue": return
	if stage == "loot_hold":
		if not _loot_waiting(runtime): _present_level_up(runtime, job)
		return
	elapsed += maxf(0.0, delta)
	if stage == "fade":
		var actor: Node2D = runtime.actor_node_for_unit(job["unit_id"])
		var ticks := minf(elapsed / OriginalTick.TICK_SECONDS, float(DEATH_TICKS))
		actor.material = death_blend
		actor.use_parent_material = false
		for child in actor.get_children():
			if child is CanvasItem: child.use_parent_material = true
		actor.scale = Vector2(1.0, 1.0 + DEATH_STRETCH_PER_TICK * ticks)
		actor.modulate.a = clampf(1.0 - ticks / float(DEATH_TICKS), 0.0, 1.0)
		if elapsed >= FADE_SECONDS:
			_dispose(actor)
			_next()
	elif stage in ["experience", "gold", "learning", "level_up"]:
		reward_label.advance(delta)
		_position_reward(runtime, job["coord"])
		if elapsed >= REWARD_RELEASE_SECONDS:
			# Released: the next phase starts while this float fades out its 46 ticks.
			if reward_label.visible:
				trailing.append({"node": reward_label, "coord": job["coord"], "lift": REWARD_LIFT})
			else:
				reward_label.queue_free()
			reward_label = _new_float()
			_next()


## 0x442720 phase 0 (static-derived, original_script_camera_scroll.md): before a recipient's
## EXP (or its $ when it gained no EXP) the camera runs 0x43bf30 on it — the battle-step glide
## that frames it at the view's (320, 192) — and the float waits until the glide lands. A
## recipient with neither EXP nor gold gets no round (and no camera). Returns whether a glide
## is running (false when the view is already there or there is no camera).
func _begin_focus(runtime: Node, coord: Vector2i) -> bool:
	var controller = _camera(runtime)
	if controller == null: return false
	focus_seconds = controller.scroll_to(BattleCameraController.focus_centre(controller.grid_cell_center_world(coord)), BattleCameraController.BATTLE_SCROLL_STEP)
	focus_count += 1
	if focus_seconds <= 0.0: return false
	stage = "focus"
	elapsed = 0.0
	return true


static func _camera(runtime: Node) -> RefCounted:
	return runtime.camera_controller if runtime != null and "camera_controller" in runtime else null


func advance_dialogue() -> void:
	if not dialogue_active() or dialogue.advance_page(): return
	dialogue.clear_message()
	_begin_disposal()


## The one entry into the fade stage for every death source; the death sound starts here, and
## the KILL float when the killer's chain is above 1 (0x43f06a..0x43f0aa, the same sub-state).
func _begin_disposal() -> void:
	stage = "fade"
	elapsed = 0.0
	var job: Dictionary = jobs[cursor]
	if int(job.get("kill_count", 0)) > 1:
		var kill: Node2D = BattleRewardFloater.new()
		kill.name = "MapKill"
		ui.add_child(kill)
		kill.present("kill", int(job["kill_count"]))
		kill.hide() # shown once placed over the victim (the next advance has the runtime)
		trailing.append({"node": kill, "coord": job["unit"]["coord"], "lift": KILL_LIFT})
	disposal_started.emit(job["unit"])


## 0x442720 phase 6: the recipient takes the use_magic pose (0x4071e0), then the LEVEL UP float
## spawns at (x, y − 48) and scatters the star shower over the recipient's point (0x4084e0 kind 6
## → 0x408b20(x, y, 3)) as sfxLevelUp sounds — the same tick.
func _present_level_up(runtime: Node, job: Dictionary) -> void:
	stage = "level_up"
	elapsed = 0.0
	var actor: Node2D = runtime.actor_node_for_unit(str(job["unit_id"])) if runtime != null and runtime.has_method("actor_node_for_unit") else null
	if actor != null and actor.has_method("play_use_magic"):
		actor.play_use_magic()
	reward_label.present("level_up")
	_position_reward(runtime, job["coord"])
	var stars: Node2D = LevelUpStars.new()
	stars.name = "LevelUpStars"
	ui.add_child(stars)
	stars.begin(("%d:%s" % [sequence, str(job["unit_id"])]).hash())
	trailing.append({"node": stars, "coord": job["coord"], "lift": 0.0})
	_place(runtime, stars, job["coord"], 0.0)
	level_up_presented.emit(job["growth"].duplicate(true))


static func _loot_waiting(runtime: Node) -> bool:
	return preload("res://game/sim/loop/BattleLoopRewards.gd").loot_waiting(runtime.play_loop) if runtime != null and "play_loop" in runtime else false


## Released reward floats fade out their remaining ticks, KILL floats hold their 40 ticks and
## LEVEL UP star showers run out, following the map (all world objects in the original).
func _advance_trailing(delta: float, runtime: Node) -> void:
	for index in range(trailing.size() - 1, -1, -1):
		var entry: Dictionary = trailing[index]
		var node: Node2D = entry["node"]
		if not node.advance(delta):
			node.queue_free()
			trailing.remove_at(index)
		else:
			_place(runtime, node, entry["coord"], float(entry["lift"]))
			node.show()


## Clears every float (developer fast-forward, a restored checkpoint).
func clear_floats() -> void:
	for entry in trailing:
		entry["node"].queue_free()
	trailing.clear()
	reward_label.hide()


func finish(runtime: Node) -> void:
	# Explicit dev fast-forward: clear only pending visuals, never replay cues/rewards.
	for index in range(cursor, jobs.size()):
		if jobs[index]["kind"] == "death":
			var actor: Node2D = runtime.actor_node_for_unit(jobs[index]["unit_id"])
			if actor != null:
				_dispose(actor)
	if dialogue_active(): dialogue.clear_message()
	clear_floats()
	cursor = jobs.size()
	stage = "idle"


## The death entry's pose: the actor's hit frame when SHAPEDEF gives it one (keys without one —
## hit_is_stand rows, authored actors — keep their current frame, as declared in the manifest).
func show_hit_pose(actor: Node2D) -> void:
	if actor.has_method("clear_highlight"): actor.clear_highlight()
	var key := str(actor.get("actor_id"))
	if hit_poses.has(key) and actor.has_method("set_shape_override"):
		actor.set_shape_override([hit_poses[key]])


## Hidden at level 0; the stretch, blend and hit pose are undone so a later reuse of the node draws normally.
func _dispose(actor: Node2D) -> void:
	if actor.has_method("clear_shape_override"): actor.clear_shape_override()
	actor.hide()
	actor.modulate.a = 0.0
	actor.scale = Vector2.ONE
	actor.material = null
	for child in actor.get_children():
		if child is CanvasItem: child.use_parent_material = false


func _position_reward(runtime: Node, coord: Vector2i) -> void:
	_place(runtime, reward_label, coord, REWARD_LIFT)


## A float stands `lift` px above its object's point and rises by its own clock.
func _place(runtime: Node, node: Node2D, coord: Vector2i, lift: float) -> void:
	var point: Vector2 = runtime.grid_cell_center_to_logical_position(coord)
	node.position = point - Vector2(0, lift + node.rise())


func _next() -> void:
	cursor += 1
	stage = "queued" if busy() else "idle"
	elapsed = 0.0


static func _unit(units: Array, id: String) -> Dictionary:
	for unit in units:
		if unit["id"] == id: return unit
	assert(false, "Missing combat receipt actor: " + id)
	return {}
