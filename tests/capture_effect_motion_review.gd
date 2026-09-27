extends SceneTree
## Frames for human review of the native effect-object motion and the cast lead's afterimages:
## 幻火 (effCode23) on a dark stand-in map at the ticks of the recording comparison
## (docs/evidence_packets/runtime_observations/effect_motion/README.md) — the falling light,
## the six fires, FireBomb2's burst of glowing sparks — then 雷歐納德's 氣刃斬 cast lead with a
## side_swapped caster (mirrored banner entering from the right, the banner's and the insets'
## afterimages). Written to ignored/r7-effect-motion/. Needs a rendered window.
##
##   tools/godot.sh --script res://tests/capture_effect_motion_review.gd
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/r7-effect-motion/"
## Script ticks after the Cast_Star lead (the comparison sheet's lower row).
const FIRE_TICKS := [2, 10, 20, 34, 52, 70, 114, 122, 135, 150]
## Cast lead calls: the banner's afterimage at (320,240) while the mirrored banner is off to
## the right (0, 8), the slide back (20), the insets with their afterimages (60, 70, 80).
const LEAD_TICKS := [0, 8, 20, 60, 70, 80]
const TICK := 1.0 / 62.5
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Effect motion review needs a rendered window")
		quit(2)
		return
	root.title = "HSL Effect Motion"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	DirAccess.make_dir_recursive_absolute(OUT)
	var ground := ColorRect.new()
	ground.color = Color(0.18, 0.15, 0.16)
	ground.size = Vector2(640, 480)
	root.add_child(ground)
	var cutin = BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var speed: float = cutin.Timing.PLAYBACK_SPEED
	# 幻火 by the 帝國法師 (026, Cast_Star lead) on one target at (326,204).
	var fire := {"skill_id": "magic:magicFIRE:magicCode01", "skill_name": "幻火", "magic_key": "fire", "magic_name": "幻火", "attacker_id": "enemy026_1", "defender_id": "leonard", "hit": true, "damage": 8, "defender_hp_before": 30, "defender_hp_after": 22, "attacker_before": {}, "defender_before": {}}
	cutin.play(fire, unit("026"), unit("001"), false, Vector2(326, 204), Vector2(250, 150))
	cutin._process(cutin.Timing.CAST_LEAD_IN / speed)
	var reached := 0
	for tick in FIRE_TICKS:
		cutin._process((tick - reached) * TICK)
		reached = tick
		await shot("huanhuo-tick%03d" % tick)
	cutin.clips.clear()
	# 氣刃斬 cast lead of a side_swapped 雷歐納德.
	var swapped := unit("001")
	swapped["side_swapped"] = true
	var blade := {"skill_id": "special:magicOTHER:magicCode01", "skill_name": "氣刃斬", "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
	cutin.play(blade, swapped, unit("021"), false)
	var lead: Dictionary = cutin.cast_lead(cutin.clips[0])
	if lead.is_empty() or not bool(lead["states"][0]["mirrored"]):
		failures.append("the side_swapped caster did not get a mirrored lead")
	reached = 0
	cutin._process(0.0001)
	for tick in LEAD_TICKS:
		cutin._process((tick - reached) * TICK)
		reached = tick
		await shot("mirrored-lead-call%03d" % tick)
	cutin.clips.clear()
	print("EFFECT_MOTION_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " shots=", FIRE_TICKS.size() + LEAD_TICKS.size())
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT + label + ".png") != OK:
		failures.append("capture " + label)


func unit(actor_id: String) -> Dictionary:
	for actor in BattleFixture.loop()["units"]:
		if str(actor["actor_id"]) == actor_id:
			return actor.duplicate(true)
	assert(false, "missing actor fixture " + actor_id)
	return {}
