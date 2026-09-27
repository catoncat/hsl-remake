extends SceneTree
## Frames of the special-skill cut-in playing its own EFFECTS.TXT script (SkillEffectScriptPlayer)
## for human review: one row per element family, three shots each (caster's shot, the hit
## mark, the result), written to ignored/r7-skill-effects/. Needs a rendered window.
##
##   tools/godot.sh --script res://tests/capture_skill_effects_review.gd [-- skill_id ...]
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/r7-skill-effects/"
## Element families: 天雷猛襲劍 (AIR, its own SP00_003 panel), 碎岩擊 (EARTH, the level-36 boss
## skill), 妖華紅蓮舞 (FIRE, aniInsertAngleObject rings), 慌雨斬 (WATER, double page), 萬息集氣法
## (WATER support), 弱體箭 (MIND status), 神怒 (OTHER, the longest script), 虛空無轉 (tornado).
const DEFAULT_ROWS := ["special:magicAIR:magicCode01", "special:magicEARTH:magicCode01", "special:magicFIRE:magicCode01", "special:magicWATER:magicCode01",
	"special:magicWATER:magicCode02", "special:magicMIND:magicCode04", "special:magicOTHER:magicCode23", "special:magicOTHER:magicCode28"]
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Skill effect review needs a rendered window")
		quit(2)
		return
	root.title = "HSL Skill Effect Scripts"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	DirAccess.make_dir_recursive_absolute(OUT)
	var cutin = BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var rows: Array = DEFAULT_ROWS if OS.get_cmdline_user_args().is_empty() else Array(OS.get_cmdline_user_args())
	var caster := unit("001")
	var target := unit("021")
	var shots := 0
	for skill_id in rows:
		var name := str(cutin.skill_effects.manifest["rows"][skill_id]["name"])
		var strike := {"skill_id": skill_id, "skill_name": name, "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
		cutin.play(strike, caster, target, false)
		cutin._process(1.0 / 60.0)
		var timeline: Dictionary = cutin.clips[0]["effect_timeline"]
		var marks := {"attack": int(timeline["release_tick"]) / 2, "impact": int(timeline["impact_tick"]) + 4, "result": int(timeline["result_tick"]) + 2}
		var tick := 1
		while cutin.busy() and tick < 3000:
			for label in marks:
				if marks[label] == tick:
					await shot("%s-%s-%s" % [skill_id.get_slice(":", 1), name, label])
					shots += 1
			cutin._process(1.0 / 60.0)
			tick += 1
		if cutin.busy():
			failures.append(skill_id + " did not complete")
			cutin.clips.clear()
	print("SKILL_EFFECTS_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " shots=", shots, " rows=", rows.size())
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
