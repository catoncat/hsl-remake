extends SceneTree
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
## GUI acceptance: normal opening + key pairs, original speed, no dev handoff.
var scene
var records: Array = []
func _initialize(): call_deferred("run")
func run():
	scene=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	DirAccess.make_dir_recursive_absolute("res://ignored/opening-continuity")
	root.add_child(scene)
	create_timer(35).timeout.connect(func():
		print("CAPTURE_TIMEOUT ", RuntimeReadback.opening_timeline_summary(scene), " interaction=", scene.interaction_state)
		quit(2))
	var seen: Dictionary={}
	while true:
		await process_frame
		var summary: Dictionary=RuntimeReadback.opening_timeline_summary(scene)
		var kind=str(summary.get("current_event_kind", ""))
		var id=str(summary.get("current_event_id", ""))
		if scene.interaction_state == "opening_timeline" and kind in ["dialogue_message_id", "section_title_resource"] and not seen.has(id):
			if kind == "section_title_resource":
				await create_timer(0.4).timeout
			RenderingServer.force_draw(false)
			var file="res://ignored/opening-continuity/%02d.png" % records.size()
			root.get_texture().get_image().save_png(file)
			records.append({"event":id,"kind":kind,"message":summary.get("current_event_message_id", ""),"actor":summary.get("current_event_actor_token", ""),"image":file,"title_visible":scene.opening_coordinator.cinematics._title != null and scene.opening_coordinator.cinematics._title.visible})
			seen[id]=true
			# Resume outside the rendering callback before delivering the key pair.
			await process_frame
			if kind == "dialogue_message_id":
				var event=InputEventKey.new()
				event.keycode=KEY_SPACE
				event.pressed=true
				Input.parse_input_event(event)
				await process_frame
				event.pressed=false
				Input.parse_input_event(event)
		if scene.interaction_state=="action_menu" and not scene.ai_playback_active and not scene.has_actor_motion():
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("res://ignored/opening-continuity/first-control.png")
			FileAccess.open("res://ignored/opening-continuity/receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"records":records,"selected_unit":scene.selected_unit_id,"menu_visible":scene.action_menu.visible},"  "))
			var messages: Array=[]
			for record in records:
				if record["kind"] == "dialogue_message_id": messages.append(record["message"])
			var passed=messages == ["363","364","365","366","367","364","1101"] and records.size() == 8 and records[7]["title_visible"] and scene.selected_unit_id == "leonard" and scene.action_menu.visible
			print("OPENING_CONTINUITY_PASS" if passed else "OPENING_CONTINUITY_FAIL")
			scene.queue_free()
			await process_frame
			await create_timer(0.2).timeout
			quit(0 if passed else 1);return
