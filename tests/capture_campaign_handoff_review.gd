extends SceneTree
## Windowed review of the campaign hand-off: first-battle victory result page with
## the next-battle button, then the carried party entering the level-52 opening.
## The victory outcome is an explicit fixture on the dev first-control seam; it is not
## a natural playthrough. Output: ignored/campaign-handoff-review/*.png + manifest.json.
const OUT := "res://ignored/campaign-handoff-review/"
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var failures: Array[String] = []
var records: Array = []


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Campaign hand-off review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Campaign Handoff Review"
	root.size = Vector2i(640, 480)
	create_timer(120).timeout.connect(func(): push_error("Campaign hand-off review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.pending = {}
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var leonard: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	leonard["level"] = 2
	leonard["exp"] = 20
	scene.play_loop["gold"] = 150
	scene.play_loop["turn"] = 8
	scene.play_loop["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	var view = scene.get_node("BattlePresentation")
	await process_frame
	await process_frame
	var confirmations := 0
	while view.dialogue_active() and confirmations < 20:
		if confirmations == 0:
			await shot(scene, "01-closing-line")
		view.advance_dialogue()
		confirmations += 1
		await process_frame
	await create_timer(0.5).timeout
	check(view.battle_finished, "the battle finishes after the closing line (no result page)")
	await shot(scene, "02-result-next-battle")
	check(scene.campaign_progress.start_next_battle(), "the finished victory hands off to the next battle")
	await process_frame
	check(CampaignProgress.has_pending() or current_scene != scene, "the finished victory stores the hand-off")
	# reload_current_scene replaces the current scene asynchronously.
	var waited := 0
	while current_scene == scene and waited < 120:
		await process_frame
		waited += 1
	var next = current_scene
	check(next != null and next != scene, "scene reloads into the next battle")
	if next == null or next == scene:
		finish(scene)
		return
	await process_frame
	await process_frame
	check(str(next.scenario_path) == "res://content/battles/battle_052.json", "reloaded scene loads the second battle")
	var carried: Dictionary = next.BattlePlayLoop.unit(next.play_loop, "leonard")
	check(int(carried.get("level", 0)) == 2 and int(next.play_loop.get("gold", 0)) == 150, "level and gold carried into level 52")
	check(next.opening_coordinator != null and next.opening_coordinator.active, "level 52 opens through the coordinator")
	await create_timer(0.3).timeout
	await shot(next, "03-next-battle-opening")
	records.append({"case": "campaign_handoff", "carry_receipt": next.play_loop.get("campaign_carry_receipt", {}),
		"save_path": next.settlement_controller.checkpoint_path, "fixture": "victory_escape outcome, level 2 / 150 gold set on the dev first-control seam"})
	finish(next)


func finish(scene: Node) -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_campaign_handoff_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	if scene != null:
		if current_scene == scene:
			current_scene = null
		scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("CAMPAIGN_HANDOFF_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("CAMPAIGN_HANDOFF_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func shot(scene: Node, label: String) -> void:
	await create_timer(0.12).timeout
	records.append({"capture": label, "interaction": scene.interaction_state, "outcome": scene.play_loop.get("battle_outcome", "")})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
