extends SceneTree
## Manual-acceptance recording of one map spell opening with the caster's own ANIMAL
## `m_action` cast lead (lane R31): the fixture's mage slot re-rowed to 緹娜 002 (P002_101
## strip — banner over the shadowed map, insets, portrait — AnimalCastLead) casts 風刃 at
## 雷歐納德 from a real play-loop receipt, then the effCode script plays on the map. A
## rendering fixture, not a natural playthrough and not a parity verdict. Raw output stays
## under ignored/.
##
##   tools/play.sh --screen 0 --write-movie ignored/r31/magic-cast.avi --fixed-fps 60 \
##     --disable-vsync --script res://tests/capture_magic_cast_review.gd
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const SPELL := "magic:magicAIR:magicCode01"
var scene: Node
var view: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The magic cast review needs an actual rendering window")
		quit(2)
		return
	root.title = "HSL — ANIMAL m_action cast lead"
	root.size = Vector2i(640, 480)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop() # Isolate the cast cue and the script's sounds.
	view = scene.get_node("BattlePresentation")
	view._map_config = scene.map_config
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var caster: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy026_1")
	caster["mp"] = 100
	var leonard: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard")
	leonard["coord"] = caster["coord"] + Vector2i(1, 0)
	# Non-lethal: with the scene's own processing paused for the fixture, a kill would leave
	# the pending death disposal in place.
	leonard["hp"] = 200
	leonard["max_hp"] = 200
	# The receipt comes from the mage's own rules (026's spell); the presentation row is then
	# 緹娜's, whose m_shape strip is imported (026's m_shape is commented out in ANIMAL.TXT).
	var receipt := BattleLoopCombat.resolve_skill(loop, caster["id"], leonard["id"], SPELL, BattlePlayLoop.skill_fields(loop, SPELL), caster["coord"], func(_n): return 0)
	caster["actor_id"] = "002"
	scene.apply_loop(loop, "test")
	scene.menus.set_action_menu_visible(false)
	scene._process(0)
	print("MAGIC_CAST_REVIEW_READY")
	await create_timer(0.5).timeout
	print("MAGIC_CAST_REVIEW_CLIP skill=", SPELL, " receipt_ok=", receipt.has("attacker_id"), " lead_ticks=", int(view.cutin.cast_lead({"attacker": "002", "attacker_base": "002"}, "magic").get("complete_tick", 0)), " frame=", Engine.get_frames_drawn())
	view._show_strike(receipt, scene.play_loop, scene.map_config, false)
	view.cutin.set_process(true)
	while view.cutin.busy():
		await process_frame
	await create_timer(0.6).timeout
	print("MAGIC_CAST_REVIEW_FINISHED frame=", Engine.get_frames_drawn())
	await create_timer(0.3).timeout
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0)
