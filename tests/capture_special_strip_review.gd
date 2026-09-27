extends SceneTree
## Frames of the 絶技 cut-in's cast lead (the caster's ANIMAL s_action over its imported
## s_shape strip, BattleCombatCutin.cast_lead) for human review: per caster row, three shots at
## fixed clip frames (banner, inset, attack phase), written to ignored/j1-special-strips/.
## A controlled fixture: the fixture's 雷歐納德 row re-keyed to each caster actor id, one
## special row for every caster; no natural playthrough. A row `base>target` is a job-up
## member (job_up_target_actor_id = target): the cut-in keys the target row and falls back to
## the base row's strip when the target declares none (006>015, 009>018). A caster without an
## imported strip shows the standing frame instead of the lead. Needs a rendered window.
##
##   tools/godot.sh --script res://tests/capture_special_strip_review.gd [-- label row ...]
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/j1-special-strips/"
const ROWS := ["004", "006", "007", "009", "053", "054", "055", "057", "006>015", "009>018"]
const SKILL_ID := "special:magicAIR:magicCode01"
## Clip frames at 60 fps: the lead's banner (panel 0), an inset, the script's attack phase.
const MARKS := {"banner": 20, "inset": 60, "attack": 130}
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Special strip review needs a rendered window")
		quit(2)
		return
	root.title = "HSL Special Strips"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	var args := Array(OS.get_cmdline_user_args())
	var label: String = args.pop_front() if not args.is_empty() else "review"
	var rows: Array = ROWS if args.is_empty() else args
	DirAccess.make_dir_recursive_absolute(OUT)
	var cutin = BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var target := unit("021")
	var shots := 0
	for row in rows:
		var actor_id := str(row).get_slice(">", 0)
		var caster := unit("001")
		caster["actor_id"] = actor_id
		if str(row).contains(">"):
			caster["job_up_target_actor_id"] = str(row).get_slice(">", 1)
		var name := str(cutin.skill_effects.manifest["rows"][SKILL_ID]["name"])
		var strike := {"skill_id": SKILL_ID, "skill_name": name, "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
		cutin.play(strike, caster, target, false)
		var strip: Array = cutin.special_frames(cutin.clips[0])
		print("SPECIAL_STRIP_ROW row=", row, " art=", cutin.clips[0]["attacker"], " panels=", strip.size(), " lead_ticks=", int(cutin.cast_lead(cutin.clips[0]).get("complete_tick", 0)))
		var frame := 0
		while cutin.busy() and frame < 3000:
			cutin._process(1.0 / 60.0)
			frame += 1
			for mark in MARKS:
				if MARKS[mark] == frame:
					await shot("J1-%s-%s-%s" % [label, str(row).replace(">", "-to-"), mark])
					shots += 1
		if cutin.busy():
			failures.append(str(row) + " did not complete")
			cutin.clips.clear()
	cutin.queue_free()
	await process_frame
	await process_frame
	print("SPECIAL_STRIP_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " shots=", shots, " rows=", rows.size())
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
	assert(false, "missing actor fixture")
	return {}
