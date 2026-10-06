extends SceneTree
## Shared presentation contracts; never claim native timing from these tests.
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
## One original tick (16 ms): the script player counts one tick per 1/62.5 s of real time.
const TICK: float = preload("res://game/common/OriginalTick.gd").TICK_SECONDS
const BattleCommandMenu = preload("res://game/battle/scene/BattleCommandMenu.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)


func unit(actor_id: String) -> Dictionary:
	for actor in BattleFixture.loop()["units"]:
		if str(actor["actor_id"]) == actor_id:
			return actor.duplicate(true)
	assert(false, "missing actor fixture")
	return {}


func dialogue_contracts() -> void:
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	root.add_child(dialogue)
	dialogue.configure_portraits(preload("res://game/sim/ContentPaths.gd").ACTOR_PORTRAITS) # the host's job; a bare board has no face table
	# Rows and pages (dialogue handler 0x414280, row breaker 0x413960; original_dialogue_board):
	# a four-row window whose row 0 is the name, a confirm scrolls up to four rows up.
	var text := "首行\n第二行\n第三行\n第四行\n第五行\n第六行\n末行。"
	dialogue.show_message("long", "雷歐納德", text, "001")
	check(dialogue.body_label.get_line_count() == 7 and dialogue.row_count() == 8, "the source's hard breaks are the body rows, under the name row")
	check(RuntimeReadback.window_rows(dialogue) == PackedStringArray(["雷歐納德:", "首行", "第二行", "第三行"]), "the first page is the name row and three body rows")
	# OPT-PACE 原版 (0x414280 reads confirm only in state 2): the wipe holds a player confirm until
	# the page is still; 快 takes it at once.
	check(dialogue.holds_confirm(), "OPT-PACE 原版: a confirm during the wipe is not read")
	var GameOptions = preload("res://game/settings/GameOptions.gd")
	GameOptions.environment_preset = GameOptions.PRESET_COMFORT
	check(not dialogue.holds_confirm(), "OPT-PACE 快: a confirm during the wipe acts at once")
	GameOptions.environment_preset = ""
	dialogue._process(dialogue.page_wipe_seconds())
	check(not dialogue.holds_confirm(), "OPT-PACE 原版: the still page reads the confirm")
	check(dialogue.advance_page(), "a long message offers another page")
	check(dialogue.holds_confirm(), "OPT-PACE 原版: a confirm during the scroll is not read")
	check(dialogue.top_row == 4 and RuntimeReadback.window_rows(dialogue) == PackedStringArray(["第四行", "第五行", "第六行", "末行。"]), "a confirm scrolls four rows up: the name scrolls away, four body rows fill the window")
	dialogue.show_message("long", "雷歐納德", text, "001")
	check(dialogue.top_row == 4, "per-frame refresh cannot reset a reader's current page")
	check(not dialogue.advance_page(), "the last page is retained until its caller accepts the next message")
	check(dialogue.body_label.text == text, "all original punctuation survives; the rows only add line breaks")
	dialogue.show_message("next", "拉爾斯帝國兵", "報告。", "021")
	check(dialogue.top_row == 0 and dialogue.portrait.texture.resource_path.ends_with("portraits/021.png"), "new speaker resets pagination and portrait together")
	var rows := BattleUISkin.message_rows("一二三四五六七八九十一二三四五六七八九十")
	check(rows == PackedStringArray(["一二三四五六七八九十一二三四五六七八九", "十"]), "a row holds 19 full-width characters (38 bytes)")
	check(BattleUISkin.message_rows("abcdefghijklmnopqrstuvwxyzabcdefghijkl一") == PackedStringArray(["abcdefghijklmnopqrstuvwxyzabcdefghijkl", "一"]), "a row holds 38 half-width characters; a full-width one past them starts the next row")
	check(BattleUISkin.message_rows("甲\n乙") == PackedStringArray(["甲", "乙"]), "the source's hard break (# → \\n) ends a row")
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/message_text_evidence.json"))["messages"]
	# Message 369 on the 2026-09-24 original recording (398.6–400.6 s): 19-glyph rows with 「！」
	# opening row 2, then a four-row scroll to body rows 4–7.
	dialogue.show_message("369", "雷歐納德", messages["369"], "001")
	check(RuntimeReadback.window_rows(dialogue) == PackedStringArray(["雷歐納德:", "..............原來..............弟兄們", "！你們也聽到了，我們已經被捨棄了，沒有", "人會來幫助我們，也沒有人會來解救我們。"]), "369 breaks into rows exactly as the recording shows: %s" % str(RuntimeReadback.window_rows(dialogue)))
	check(dialogue.advance_page() and RuntimeReadback.window_rows(dialogue) == PackedStringArray(["看看地上，這些因此而犧牲的同伴，為了他", "們，也為了我們自己，我們絕不能就此放棄", "，現在只有一條路可走，想活命的就跟著我", "!!"]), "369's confirm scrolls four rows to the recording's last page: %s" % str(RuntimeReadback.window_rows(dialogue)))
	check(not dialogue.advance_page(), "369 has two pages")
	for id in ["363", "369", "370"]:
		var body: String = messages[id]
		dialogue.show_message(id, "雷歐納德", body, "001")
		var seen := {}
		for _guard in range(20):
			check(RuntimeReadback.window_rows(dialogue).size() <= dialogue.WINDOW_ROWS, "source speech stays inside the four-row window")
			for row in range(dialogue.top_row, mini(dialogue.row_count(), dialogue.top_row + dialogue.WINDOW_ROWS)):
				seen[row] = true
			var before: int = dialogue.top_row
			if not dialogue.advance_page(): break
			check(dialogue.top_row - before >= 1 and dialogue.top_row - before <= dialogue.SCROLL_ROWS, "a confirm scrolls one to four rows")
		check(seen.size() == dialogue.row_count() and dialogue.body_label.text.replace("\n", "") == body, "source speech has every row shown and no character omitted: " + id)
		dialogue.clear_message()
	# A shorter scroll keeps earlier rows in view (the original scrolls only the rows left).
	dialogue.show_message("short", "雷歐納德", "一\n二\n三\n四\n五", "001")
	check(dialogue.advance_page() and RuntimeReadback.window_rows(dialogue) == PackedStringArray(["二", "三", "四", "五"]), "two rows left: the scroll moves two rows and 二／三 stay in view")
	dialogue.show_narration("narr", "一\n二\n三\n四\n五")
	check(RuntimeReadback.window_rows(dialogue) == PackedStringArray(["一", "二", "三", "四"]) and not dialogue.speaker_label.visible, "narration has no name row: four body rows in view")
	dialogue.clear_message()
	check(not dialogue.visible and dialogue.body_label.text == "", "closing removes stale dialogue content")
	# Board placement (dialogue handler 0x414280 init): a cast member's line sits at (144,320),
	# a script-faced line (actShapeMessage, flag 0x4000) at y 20, speakerless narration centred.
	dialogue.show_message("place1", "雷歐納德", "首行", "001")
	check(dialogue.position == Vector2(0, 320), "a cast member's line takes the bottom slot, board left 144")
	dialogue.show_face_message("place2", "???", "首行", "SHAPE\\FACE0054.SHP")
	check(dialogue.position == Vector2(0, 20), "a script-faced line takes the top slot at y 20 (flag 0x4000)")
	dialogue.show_narration("place3", "旁白。")
	check(dialogue.position + dialogue.BOARD_AT == Vector2(75, 320), "speakerless narration centres the board: left (640 - 489) / 2 = 75")
	dialogue.show_narration("place4", "雷歐納德：請選擇", false)
	check(dialogue.position + dialogue.BOARD_AT == Vector2(144, 320), "a host's line naming a speaker keeps the speaker board's place")
	dialogue.clear_message()
	# Dissolves and the line wipe (runtime-measured, dialogue_death packet): visual only.
	var ghosts := func() -> int:
		return root.get_children().filter(func(n): return str(n.name).begins_with("DialogueDissolve")).size()
	await create_timer(dialogue.DISSOLVE_OUT_SECONDS + 0.2).timeout
	check(ghosts.call() == 0, "the closes above left dissolving copies that are gone after %.2f s" % dialogue.DISSOLVE_OUT_SECONDS)
	dialogue._process(1.0)
	dialogue.show_message("wipe", "雷歐納德", "首行\n第二行\n第三行", "001")
	dialogue._process(0.0)
	check(dialogue.visible and dialogue.modulate.a < 0.05 and dialogue.text_window.size.y == dialogue.WIPE_START_PIXELS, "a new board starts transparent with only the first 17 px of its text window uncovered")
	check(dialogue.reveal_height(1) == 17.0 and dialogue.reveal_height(2) == 20.0 and dialogue.reveal_height(32) == 110.0 and dialogue.reveal_height(33) == 112.0 and dialogue.reveal_height(90) == 112.0, "the wipe grows 3 px a tick from 17 px to the four rows' 112 px")
	var tick: float = dialogue.OriginalTick.TICK_SECONDS
	dialogue._process(dialogue.DISSOLVE_IN_SECONDS)
	check(is_equal_approx(dialogue.DISSOLVE_IN_SECONDS, 16 * tick) and is_equal_approx(dialogue.modulate.a, 1.0), "the board has faded in after 16 ticks")
	check(dialogue.text_window.size.y == dialogue.reveal_height(16.0), "the text wipes in with the fade, top-down (%.1f px after 16 ticks)" % dialogue.text_window.size.y)
	dialogue._process(dialogue.page_wipe_seconds())
	check(dialogue.text_window.size.y == dialogue.WINDOW_PIXELS, "the whole window is wiped in after %.3f s" % dialogue.page_wipe_seconds())
	dialogue.show_message("wipe2", "拉爾斯帝國兵", "報告。", "021")
	check(ghosts.call() == 1 and dialogue.speaker_label.text == "拉爾斯帝國兵:", "a speaker change leaves the old board dissolving out while the new message is already current")
	dialogue._process(0.0)
	check(dialogue.modulate.a == 0.0 and dialogue._board_clock < 0.0, "the new board waits for the old one to dissolve out")
	dialogue.clear_message()
	check(not dialogue.visible and ghosts.call() == 2, "closing hides the board at once and leaves a dissolving copy (no input or logic)")
	await create_timer(dialogue.DISSOLVE_OUT_SECONDS + 0.2).timeout
	check(ghosts.call() == 0, "the dissolving copies free themselves after %.2f s" % dialogue.DISSOLVE_OUT_SECONDS)
	# Page marker (dialogue handler 0x414280): ▼ while another page follows, □ on the last page,
	# at the board's bottom-right minus 30 px, blinking 10 ticks shown／10 hidden after the wipe.
	check(not dialogue.marker_shown(-0.01) and dialogue.marker_shown(0.0) and dialogue.marker_shown(9.5 * tick) and not dialogue.marker_shown(10.5 * tick) and not dialogue.marker_shown(19.5 * tick) and dialogue.marker_shown(20.5 * tick), "the marker blinks 10 ticks shown, 10 hidden, from the end of the wipe")
	dialogue.show_message("marker", "雷歐納德", "一\n二\n三\n四\n五", "001")
	dialogue._process(0.0)
	check(not dialogue.continue_label.visible and not dialogue.end_marker.visible, "no marker while the page is still wiping in")
	dialogue._reveal_clock = dialogue.page_wipe_seconds() + 0.001
	dialogue._process(0.0)
	check(dialogue.continue_label.visible and dialogue.continue_label.text == "▼" and not dialogue.end_marker.visible, "another page follows: the ▼ glyph, no page count")
	dialogue._process(10.5 * tick)
	check(not dialogue.continue_label.visible, "the ▼ glyph blinks off after 10 ticks")
	check(dialogue.advance_page(), "the five-line message has a second page")
	dialogue._process(0.0)
	check(not dialogue.continue_label.visible and not dialogue.end_marker.visible, "a scrolling page hides the marker until it is still")
	check(dialogue.scroll_offset(0, 4) == 0.0 and dialogue.scroll_offset(1, 4) == 3.0 and dialogue.scroll_offset(9, 4) == 27.0 and dialogue.scroll_offset(10, 4) == 28.0 and dialogue.scroll_offset(40, 4) == 112.0 and dialogue.scroll_offset(99, 2) == 56.0, "the scroll moves 3 px a tick and shifts a row every 10 ticks")
	check(dialogue.text_rows.position.y == 0.0, "the rows start the scroll where the first page left them")
	dialogue._process(5.5 * tick)
	check(dialogue.text_rows.position.y == -15.0, "five ticks into the scroll the rows are 15 px up (%.1f)" % dialogue.text_rows.position.y)
	dialogue._process(15.0 * tick)
	check(dialogue.text_rows.position.y == -2 * dialogue.ROW_PITCH, "two rows (20 ticks) later the scroll has settled two rows up")
	dialogue._reveal_clock = dialogue.page_wipe_seconds() + 0.001
	dialogue._process(0.0)
	check(dialogue.end_marker.visible and not dialogue.continue_label.visible and dialogue.continue_label.text == "", "the last page shows the □ marker")
	check(dialogue.position + dialogue.end_marker.position == Vector2(605, 438) and dialogue.end_marker.size.x == dialogue.END_MARKER_SIZE + 1.0, "the □ ink sits at (605,438) on the bottom board, 20 px with its shadow line")
	dialogue.clear_message()
	await create_timer(dialogue.DISSOLVE_OUT_SECONDS + 0.2).timeout
	# The speaking map actor carries the shared "speaker" highlight while its message is up.
	var Actor = preload("res://game/battle/runtime/ActorRuntime.gd")
	var speaker_a: Node2D = Actor.new()
	var speaker_b: Node2D = Actor.new()
	root.add_child(speaker_a)
	root.add_child(speaker_b)
	dialogue.set_speaker_actor(speaker_a)
	dialogue.show_message("spk1", "雷歐納德", "首行", "001")
	check(RuntimeReadback.highlight_kind(speaker_a) == "speaker", "the speaker is lit while its message is up")
	dialogue.show_message("spk1", "雷歐納德", "首行", "001")
	check(RuntimeReadback.highlight_kind(speaker_a) == "speaker", "a per-frame refresh of the same message keeps the speaker lit")
	dialogue.set_speaker_actor(speaker_b)
	dialogue.show_message("spk2", "拉爾斯帝國兵", "報告。", "021")
	check(RuntimeReadback.highlight_kind(speaker_a) == "" and RuntimeReadback.highlight_kind(speaker_b) == "speaker", "the light moves with the speaker change")
	dialogue.show_narration("spk3", "旁白。")
	check(RuntimeReadback.highlight_kind(speaker_b) == "", "narration has no speaker to light")
	dialogue.set_speaker_actor(speaker_a)
	dialogue.show_message("spk4", "雷歐納德", "首行", "001")
	dialogue.clear_message()
	check(RuntimeReadback.highlight_kind(speaker_a) == "", "closing the board releases the speaker")
	speaker_a.set_highlight("target", true)
	speaker_a.set_highlight("speaker", true)
	check(RuntimeReadback.highlight_kind(speaker_a) == "speaker", "speaker outranks target (one highlight at a time)")
	speaker_a.set_highlight("speaker", false)
	check(RuntimeReadback.highlight_kind(speaker_a) == "target", "releasing the speaker leaves the target light")
	speaker_a.clear_highlight()
	check(RuntimeReadback.highlight_kind(speaker_a) == "", "clearing removes the light")
	speaker_a.free()
	speaker_b.free()
	dialogue.free()
	await process_frame


func run() -> void:
	await dialogue_contracts()
	var camera_rules = preload("res://game/common/BattleCameraController.gd")
	var scroll_oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_mechanics_audit_scroll.json"))
	var checked_edges := 0
	for sample in scroll_oracle["cases"]:
		if int(sample["input_flags"]) != 0:
			continue
		var point := Vector2(sample["viewport_pointer"][0], sample["viewport_pointer"][1])
		if not Rect2(0, 0, 640, 480).has_point(point):
			continue
		var expected := Vector2(sample["delta"][0], sample["delta"][1])
		check(camera_rules.edge_direction(point, true) * 12 == expected, "edge input must match the original strict threshold request")
		checked_edges += 1
	check(checked_edges > 10, "edge oracle must exercise more than one boundary")
	check(camera_rules.edge_direction(Vector2(9, 9), false) == Vector2.ZERO, "inactive pointer must not move the map")
	check(camera_rules.edge_direction(Vector2(-1, 9), true) == Vector2.ZERO, "outside-window pointer must not move the map")
	await inventory_contracts()
	await cast_overlay_contracts()
	await lead_in_contracts()
	await ai_cue_camera_area_contracts()
	await area_special_contracts()
	sprite_key_contracts()
	identity_mask_contracts()
	aftermath_contracts()
	skill_effect_contracts()
	# Golden traces were obtained by executing the version-checked original
	# machine instructions with synthetic objects, not by this Godot model.
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/native_presentation_helpers.json"))
	check(oracle["frame_cases"].size() == 8 and oracle["opening_cases"].size() == 6, "native oracle must retain every bounded case")
	for sample in oracle["frame_cases"]:
		for update in range(sample["frame_by_update"].size()):
			check(BattleCommandMenu.PresentationRules.frame_at(int(sample["frames"]), update, sample["mode"] == "loop") == int(sample["frame_by_update"][update]), "frame update differs from native %s/%d at call %d" % [sample["mode"], sample["frames"], update])
	for sample in oracle["opening_cases"]:
		var target := Vector2i(sample["target"][0], sample["target"][1])
		for i in range(1, sample["positions"].size()):
			var previous := Vector2i(sample["positions"][i - 1][0], sample["positions"][i - 1][1])
			var expected := Vector2i(sample["positions"][i][0], sample["positions"][i][1])
			check(BattleCommandMenu.PresentationRules.opening_step(previous, target) == expected, "opening interpolation differs from original helper")
	var menu := BattleCommandMenu.new()
	root.add_child(menu)
	menu.set_process(false)
	menu.rebuild([{"command": "move", "enabled": true}, {"command": "attack", "enabled": true}, {"command": "special", "enabled": true}, {"command": "item", "enabled": true}, {"command": "status", "enabled": true}, {"command": "wait", "enabled": true}])
	menu.place_near(Vector2(320, 240), Rect2(0, 0, 640, 480))
	var anchor := menu.position
	check(menu.is_expanding(), "a rebuilt menu expands from its owner rather than appearing in final slots")
	check(menu.displayed_centers["move"] == Vector2.ZERO, "native opening starts all icons at the center")
	menu._process(1.0 / 60.0)
	check(menu.displayed_centers["move"] == Vector2(0, -8), "opening uses the native bounded integer step")
	menu._process(0.25)
	check(not menu.is_expanding() and menu.displayed_centers == menu.centers, "opening converges to the same visible and clickable layout")
	menu.set_hovered_command("move")
	var first: Texture2D = menu.get_node("MoveCommand").texture_normal
	menu._process(0.14)
	var second: Texture2D = menu.get_node("MoveCommand").texture_normal
	check(first != second, "hover must consume another source frame, not only enlarge frame zero")
	menu.set_hovered_command("move")
	check(menu.hover_elapsed > 0, "repeated pointer refresh must not restart the hover clock")
	menu._process(0.14)
	check(menu.get_node("MoveCommand").texture_normal != second, "hover retains all three source poses")
	menu.set_hovered_command("")
	check(menu.get_node("MoveCommand").texture_normal == first, "hover exit resets idle pose")
	check(menu.position == anchor, "animation cannot move the menu hit-test anchor")
	check(menu.get_node("SpecialCommand").position.x > 0 and menu.get_node("ItemCommand").position.x < 0, "special upper-right and item lower-left follow the original reference")
	check(BattleCommandMenu.PresentationRules.centers(2) == [Vector2(0, -72), Vector2(0, 72)], "two remaining commands have a complete opposite layout, not holes")
	check(BattleCommandMenu.PresentationRules.frame_at(3, 21, false) == 1, "three-frame menus reverse instead of wrapping from the last pose")
	check(BattleCommandMenu.PresentationRules.frame_at(5, 35, true) == 0, "status uses its source loop flag rather than ping-pong")
	menu.hide()
	menu.show()
	check(menu.is_expanding() and menu.hover_elapsed == 0.0, "reopening resets only visual expansion and hover")
	menu.queue_free()
	await process_frame
	# Exercise each display frame rather than seeking directly to one selected pose.
	for fps in [30, 60]:
		var cutin := BattleCombatCutin.new()
		root.add_child(cutin)
		cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
		cutin.set_process(false)
		var events: Array[String] = []
		cutin.released.connect(func(_s, _a, _d, _c): events.append("release"))
		cutin.impact.connect(func(_s, _a, _d, _c): events.append("impact"))
		for hit in [true, false]:
			events.clear()
			var actor := unit("001")
			var defender := unit("021")
			var before := [actor.duplicate(true), defender.duplicate(true)]
			cutin.play({"hit": hit, "damage": 5 if hit else 0, "defender_hp_before": 22, "defender_hp_after": 17 if hit else 22}, actor, defender, false)
			var counts := {"opening": 0, "windup": 0, "release": 0, "target_pause": 0, "hurt": 0, "recovery": 0, "closing": 0}
			var schedule := cutin.Timing.ordinary(cutin.manifest["actors"]["001"], cutin.clips[0]["strike"])
			var guard := 0
			while cutin.busy() and guard < fps * 10:
				cutin._process(1.0 / fps)
				guard += 1
				if not cutin.busy():
					break
				var phase := RulesReadback.phase_at(schedule, cutin.elapsed)
				counts[phase] += 1
				if phase == "opening":
					var zoom_stage: bool = cutin.elapsed < cutin.OriginalTick.seconds(cutin.Timing.OPENING_ZOOM_TICKS)
					var wait_tick: bool = cutin.elapsed >= cutin.OriginalTick.seconds(cutin.Timing.OPENING_ZOOM_TICKS + cutin.Timing.OPENING_OVERLAY_TICKS)
					check(cutin.opening_ball.visible != wait_tick and not cutin.defender_sprite.visible and not cutin.clips[0]["release_emitted"], "the opening ball plays before the attacker's program; phase 100 sub-state 2 (0x4027ee) waits one tick without it")
					check(zoom_stage == (cutin.opening_ball.material != null) and zoom_stage == (not cutin.attacker_sprite.visible) and zoom_stage == (not cutin.vitals.visible), "the zoom draws are additive with the attacker and board hidden; the overlay fades over the restored attacker and the board")
					check(zoom_stage == (not cutin.scenery.visible) and zoom_stage == (not cutin.background.visible), "the zoom grows over the battlefield map; the close-up backdrop returns with the overlay (camera_panel_motion §5)")
					if not zoom_stage:
						check(cutin.opening_ball.scale.x == 18.0 and cutin.opening_ball.modulate.a <= 1.0 and cutin.opening_ball.modulate.a >= 1.0 / 16.0, "the overlay is the ball at 18× blended at level 16 → 1")
				if phase == "windup":
					check(not cutin.opening_ball.visible and not cutin.transition_shade.visible and cutin.vitals.visible, "the program plays without the opening ball or the shade")
				if phase == "recovery":
					check(cutin.defender_sprite.visible and cutin.transition_shade.visible and cutin.transition_shade.color.a > 0.0 and cutin.transition_shade.color.a <= 1.0 and cutin.defender_sprite.texture.resource_path.ends_with("021/4.png" if hit else "021/0.png"), "the darken rises over the held hurt shot; no return-to-neutral pose")
				if phase == "closing":
					check(cutin.transition_shade.visible and not cutin.scenery.visible and not cutin.vitals.visible and not cutin.defender_sprite.visible, "the lighten plays over the map with the cut-in contents hidden")
				if phase == "target_pause":
					check(cutin.defender_sprite.visible and not cutin.clips[0]["impact_emitted"], "victim has a distinct pre-impact shot")
					check(cutin.vitals.values["hp"].text == "22/22", "pending victim shot must retain pre-hit HP")
				if phase == "hurt":
					check(cutin.defender_sprite.visible, "victim must remain visible throughout hurt interval")
					check(cutin.defender_sprite.texture.resource_path.ends_with("021/4.png" if hit else "021/0.png"), "hit and miss have distinct victim poses")
			check(events == ["release", "impact"], "swing and hit must be ordered, separate, and exactly once")
			# Receiver budgets are AnimalDefense ticks at 16 ms: 32-tick neutral pause (0.512 s);
			# a one-digit hit holds 40 ＋ 37 ＋ 1 = 78 ticks (1.248 s), a miss 15 ＋ 1 ＋ 40 = 56 (0.896 s).
			check(counts["target_pause"] >= fps * 0.5 and counts["hurt"] >= fps * (1.2 if hit else 0.85), "receiver stages cannot collapse into a single display frame")
			# Opening 24 ＋ 32 ＋ 1 = 57 ticks (0.912 s); closing darken 16 (0.256 s) and lighten 16 ticks.
			check(counts["opening"] >= fps * 0.85 and counts["recovery"] >= fps * 0.2 and counts["closing"] >= fps * 0.2, "the first-shot opening and the last-shot transition play their tick budgets")
			check(cutin.Timing.hurt_hold_ticks(hit, 5) == (78 if hit else 56), "the hurt hold follows the defender object's counters: 40 ticks to the number plus its release on a hit, the 150 px slide plus 40 on a miss")
			check(cutin.Timing.OPENING_ZOOM_RAMP.size() == 24 and cutin.Timing.OPENING_ZOOM_RAMP[0] == 0x1000 and cutin.Timing.OPENING_ZOOM_RAMP[23] == 0xc4000 and cutin.Timing.opening_overlay_level(0) == 16 and cutin.Timing.opening_overlay_level(31) == 1, "the 0x401060 ramp draws 24 zooms from 1/16 to 12.25 and the overlay level walks 16 → 1 over 32 ticks")
			var mid := cutin.Timing.ordinary(cutin.manifest["actors"]["001"], {"hit": hit, "damage": 5, "defender_hp_after": 17}, false, false)
			check(float(mid["opening"]) == 0.0 and mid["recovery"] == mid["darkened"] and is_equal_approx(float(mid["complete"]), float(mid["darkened"]) + cutin.Timing.HANDOVER), "a shot inside an exchange (counter or extra strike pending) skips the opening and the transition and hands over one tick later (0x404b23 sub-state 0 → sub-state 2 at 0x404b55)")
			var kill := cutin.Timing.ordinary(cutin.manifest["actors"]["001"], {"hit": true, "damage": 5, "defender_hp_after": 0}, false, false)
			check(float(kill["complete"]) - float(kill["recovery"]) > 0.5, "a killing blow closes the exchange with the transition even when more strikes were queued")
			check(actor == before[0] and defender == before[1], "presentation must not mutate combat truth")
		cutin.queue_free()
		await process_frame
	# A magic receipt plays its effCode script through the script player (the skill_id names
	# the row); 026 has no strip: 8 shadow calls, then the Cast_Star burst over the caster with
	# sfx 0x193 (0x403128..0x40318c), the script then plays at the target.
	var magic := BattleCombatCutin.new()
	root.add_child(magic)
	magic.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	magic.set_process(false)
	magic.play({"skill_id": "magic:magicAIR:magicCode01", "magic_key": "wind", "magic_name": "風刃", "hit": true, "damage": 5, "defender_hp_after": 25}, unit("026"), unit("001"), false, Vector2(470, 320), Vector2(190, 210))
	magic.clips[0]["caster_pose_ticks"] = 88
	magic._process(magic.Timing.CAST_LEAD_IN / magic.Timing.PLAYBACK_SPEED + 0.3)
	check(magic.ability_sound.stream.resource_path.ends_with("cast_magic.wav"), "casting begins with its independent original sound")
	var stars: Array = magic.skill_effects.sprites.filter(func(sprite): return sprite.visible and sprite.texture.resource_path.contains("cast_star"))
	check(not stars.is_empty(), "casting consumes source Cast_Star frames")
	check(stars.all(func(sprite): return sprite.position.distance_to(Vector2(190, 168)) < 200 and sprite.position.x < 400), "casting effect anchors at caster, not target")
	check(not magic.clips[0]["impact_emitted"] and not magic.result.visible, "casting must not announce target damage, and carries no name caption: the original captions a spell only while its range is drawn")
	magic._process(88.0 / 62.5 / magic.Timing.PLAYBACK_SPEED)
	var shown: Array = magic.skill_effects.sprites.filter(func(sprite): return sprite.visible and not sprite.texture.resource_path.contains("cast_star"))
	check(not shown.is_empty() and shown.all(func(sprite): return sprite.position.x > 400) and shown[0].texture.resource_path.contains("air01_"), "released effect moves to the target side of the map, drawing the script's AirWave1 shapes")
	magic._process(10)
	check(not magic.busy() and not magic.skill_effects.visible, "spell releases the same presentation gate at completion")
	magic.queue_free()
	await process_frame
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("PRESENTATION_CONTRACT_TESTS_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


## A stand-in for the runtime seams BattleAftermath.advance touches: one map actor per
## defeated unit and a fixed reward anchor.
class AftermathStubRuntime extends Node:
	var actors := {}
	func actor_node_for_unit(unit_id: String) -> Node2D:
		if not actors.has(unit_id):
			actors[unit_id] = Node2D.new()
			add_child(actors[unit_id])
		return actors[unit_id]
	func grid_cell_center_to_logical_position(_coord: Vector2i) -> Vector2:
		return Vector2(320, 240)


## Death-line data contract (content/generated/hsl/combat/aftermath.json): every PLAYERS row
## is declared — rows with a dead_message speak (049 魔騎士, 008 咕嚕 under its party name),
## rows without one fall silently (`messages: []`). A receipt whose fallen actor is outside the
## table is reported (push_error) and still completes as a silent fade, never a busy() lock;
## a receipt with one declared and one undeclared victim finishes both.
func aftermath_contracts() -> void:
	var aftermath = preload("res://game/battle/scene/BattleAftermath.gd").new()
	var runtime := AftermathStubRuntime.new()
	root.add_child(runtime)
	root.add_child(aftermath)
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	root.add_child(dialogue)
	dialogue.configure_portraits(preload("res://game/sim/ContentPaths.gd").ACTOR_PORTRAITS)
	aftermath.dialogue = dialogue
	var actors: Dictionary = aftermath.source["actors"]
	# 66 PLAYERS.TXT rows plus the authored characters (content/authored/roles/characters.json), each a silent row unless it declares a dead_message.
	var authored: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/authored/roles/characters.json")).get("characters", [])
	check(actors.size() == 66 + authored.size() and actors.has("049") and actors.has("005") and actors.has("101"), "aftermath.json declares every PLAYERS character row (66) and every authored character, not only the first-battle cast")
	check(authored.all(func(row): return actors.has(str(row["code"]).pad_zeros(3)) and actors[str(row["code"]).pad_zeros(3)]["messages"].is_empty()), "authored characters without a dead_message are declared silent rows")
	check(actors["049"]["speaker"] == "魔騎士" and str(actors["049"]["messages"][0]["id"]) == "1570", "049 speaks its PLAYERS dead_message under its job_show_name")
	check(actors["008"]["speaker"] == "咕嚕" and str(actors["008"]["messages"][0]["id"]) == "1825", "008 (no job_show_name) speaks under its party name")
	check(actors["005"]["messages"].is_empty() and aftermath.source["silent_actors"].has("005"), "005 is a declared silent row, not a missing template")
	var units := [
		{"id": "sheila", "actor_id": "005", "coord": Vector2i(3, 3), "hp": 0},
		{"id": "stranger", "actor_id": "999", "coord": Vector2i(4, 3), "hp": 0},
		{"id": "rider", "actor_id": "049", "coord": Vector2i(5, 3), "hp": 0},
		{"id": "killer", "actor_id": "055", "coord": Vector2i(5, 5), "hp": 40},
	]
	var sweep := {"sequence": 1, "attacker_id": "killer", "defender_id": "sheila", "hit": true, "damage": 30, "defender_hp_before": 12, "defender_hp_after": 0,
		"affected_targets": [
			{"defender_id": "sheila", "hit": true, "actual_damage": 12, "defender_hp_before": 12, "defender_hp_after": 0},
			{"defender_id": "stranger", "hit": true, "actual_damage": 9, "defender_hp_before": 9, "defender_hp_after": 0},
			{"defender_id": "rider", "hit": true, "actual_damage": 20, "defender_hp_before": 20, "defender_hp_after": 0}]}
	check(aftermath.defeated_ids(sweep) == ["sheila", "stranger", "rider"], "three victims of one exchange")
	# The undeclared row is reported through push_error (the strict harness fails on any
	# console ERROR line); the report itself is expected here, so console printing is paused.
	Engine.print_error_messages = false
	aftermath.prepare(sweep, units)
	Engine.print_error_messages = true
	check(aftermath.busy() and aftermath.stage == "queued" and aftermath.jobs.size() == 3, "an undeclared victim does not abort the queue: all three deaths are queued and the stage is set")
	check(aftermath.jobs[0]["message"].is_empty() and aftermath.jobs[1]["message"].is_empty() and str(aftermath.jobs[1]["actor_id"]) == "999", "declared-silent 005 and undeclared 999 both fall without a line")
	check(str(aftermath.jobs[2]["message"]["id"]) == "1570" and aftermath.jobs[2]["speaker"] == "魔騎士", "049's source last words are queued")
	var guard := 0
	while aftermath.busy() and guard < 600:
		guard += 1
		aftermath.advance(1.0 / 60.0, runtime)
		if aftermath.dialogue_active():
			check(dialogue.visible and dialogue.speaker_label.text == "魔騎士:", "the 049 line is shown with its speaker (shared portrait row)")
			aftermath.advance_dialogue()
	check(not aftermath.busy() and aftermath.stage == "idle" and guard < 600, "the exchange completes (fade, line, fade) instead of locking combat_busy")
	check(not runtime.actors["stranger"].visible and not runtime.actors["sheila"].visible and not runtime.actors["rider"].visible, "every fallen actor is hidden after its fade")
	dialogue.free()
	aftermath.free()
	runtime.free()
	install_dead_message_contracts()


## Death line of a unit whose placed object installed obj_Data8 (0x407ec0 → live +0x14, unit
## `dead_message`): level 34's villagers (062, a row without a dead_message) speak 373 under
## their 稱號; level 24's placed 024 and level 44's placed 023 carry −1 (an empty list) and
## fall silently instead of speaking the 024／023 row pair 374／375; level 44's inserted 021
## packs two ids (0x08d708d8 → 2263 first, 2264 second) and the remake shows the first.
func install_dead_message_contracts() -> void:
	var aftermath = preload("res://game/battle/scene/BattleAftermath.gd").new()
	var runtime := AftermathStubRuntime.new()
	root.add_child(runtime)
	root.add_child(aftermath)
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	root.add_child(dialogue)
	dialogue.configure_portraits(preload("res://game/sim/ContentPaths.gd").ACTOR_PORTRAITS)
	aftermath.dialogue = dialogue
	var thirty_four: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_034.json"))
	var villagers: Array = thirty_four["playable_units"].filter(func(row): return str(row["actor_id"]) == "062")
	check(villagers.size() == 3 and villagers.all(func(row): return row.has("dead_message") and str(row["dead_message"]["messages"][0]["id"]) == "373" and str(row["dead_message"]["speaker"]) == "村民"), "battle_034 carries obj_Data8 373 on all three placed villagers (their PLAYERS row has no dead_message)")
	check(aftermath.death_template("062")["messages"].is_empty(), "the 062 row template itself is silent")
	var twenty_four: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_024.json"))
	var captains: Array = twenty_four["playable_units"].filter(func(row): return str(row["actor_id"]) == "024")
	check(captains.size() == 6 and captains.all(func(row): return row.has("dead_message") and row["dead_message"]["messages"].is_empty()), "battle_024 carries the −1 clear on all six placed 024 (row pair 374／375 silenced)")
	var forty_four: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/battle_044.json"))
	var soldiers: Array = forty_four["playable_units"].filter(func(row): return str(row["actor_id"]) == "023")
	check(soldiers.size() == 19 and soldiers.all(func(row): return row.has("dead_message") and row["dead_message"]["messages"].is_empty()), "battle_044's nineteen placed 023 carry the −1 clear")
	var imperial: Dictionary = forty_four["script_actor_templates"]["obj_Story_Level_Enemy21"]["actor"]
	check(imperial["dead_message"]["messages"].map(func(row): return str(row["id"])) == ["2263", "2264"] and str(imperial["dead_message"]["speaker"]) == "拉爾斯帝國兵", "battle_044's inserted 021 unpacks 0x08d708d8 as first 2263, second 2264")
	var villager: Dictionary = villagers[0].duplicate(true)
	villager.merge({"id": "villager", "coord": Vector2i(3, 3), "hp": 0}, true)
	var captain: Dictionary = captains[0].duplicate(true)
	captain.merge({"id": "captain", "coord": Vector2i(4, 3), "hp": 0}, true)
	var plain_captain := {"id": "plain_captain", "actor_id": "024", "coord": Vector2i(5, 3), "hp": 0}
	var soldier: Dictionary = imperial.duplicate(true)
	soldier.merge({"id": "soldier", "coord": Vector2i(6, 3), "hp": 0}, true)
	var units := [villager, captain, plain_captain, soldier, {"id": "killer", "actor_id": "001", "coord": Vector2i(5, 5), "hp": 40}]
	var sweep := {"sequence": 1, "attacker_id": "killer", "defender_id": "villager", "hit": true, "damage": 30, "defender_hp_before": 12, "defender_hp_after": 0,
		"affected_targets": [
			{"defender_id": "villager", "hit": true, "actual_damage": 12, "defender_hp_before": 12, "defender_hp_after": 0},
			{"defender_id": "captain", "hit": true, "actual_damage": 9, "defender_hp_before": 9, "defender_hp_after": 0},
			{"defender_id": "plain_captain", "hit": true, "actual_damage": 9, "defender_hp_before": 9, "defender_hp_after": 0},
			{"defender_id": "soldier", "hit": true, "actual_damage": 9, "defender_hp_before": 9, "defender_hp_after": 0}]}
	aftermath.prepare(sweep, units)
	check(aftermath.jobs.size() == 4 and str(aftermath.jobs[0]["message"]["id"]) == "373" and aftermath.jobs[0]["speaker"] == "村民", "the level-34 villager speaks its installed 373 under its 稱號")
	check(aftermath.jobs[1]["message"].is_empty(), "the −1 captain falls silently")
	# 0x43efaf picks a pair half with the death-branch roll (the remake's hash of exchange and victim).
	var plain_line := str(aftermath.choose_dead_message(aftermath.death_template("024")["messages"], aftermath.dead_message_roll(1, "plain_captain"))["id"])
	var packed_line := str(aftermath.choose_dead_message(imperial["dead_message"]["messages"], aftermath.dead_message_roll(1, "soldier"))["id"])
	check(plain_line in ["374", "375"] and str(aftermath.jobs[2]["message"]["id"]) == plain_line and aftermath.jobs[2]["speaker"] == "重裝兵", "a 024 without the install word speaks the rolled half of its row pair")
	check(packed_line in ["2263", "2264"] and str(aftermath.jobs[3]["message"]["id"]) == packed_line and aftermath.jobs[3]["speaker"] == "拉爾斯帝國兵", "the packed pair shows the rolled half of its high／low words")
	var spoken: Array[String] = []
	var guard := 0
	while aftermath.busy() and guard < 600:
		guard += 1
		aftermath.advance(1.0 / 60.0, runtime)
		if aftermath.dialogue_active():
			spoken.append(dialogue.speaker_label.text + aftermath.current_message_id())
			aftermath.advance_dialogue()
	check(spoken == ["村民:373", "重裝兵:" + plain_line, "拉爾斯帝國兵:" + packed_line] and not aftermath.busy(), "three lines are shown in order, the silenced captain only fades")
	dialogue.free()
	aftermath.free()
	runtime.free()


## Which PLAYERS row draws a job-up member (ActorSpriteKey): the target row when its
## frames / face are imported, the base row otherwise; the level manifest wins over the
## shared up-title manifest. Pure lookups — the vitals panel and the runtime spawn share them.
## Special skills cut in with their own EFFECTS.TXT scripts: every row skill_effects/manifest.json
## routes to the script player runs through the cut-in to completion with exactly one release
## and one impact, in the order the compiled timeline names, drawing at least one script
## object; the aniInsertSpecialBG panel replaces 氣刃斬's SP00_001; the title shows during the
## caster's shot and the result after aniShowHitResult; a strike without a skill_id and the
## two dedicated rows never enter the player. Every magic row plays its effCode script on the
## map through the same presenter: one release at the end of the cast lead, one impact at the
## script's last cue, at least one object drawn, the map presenter's shot (no backdrop, no
## actors, the 480-high stage, the spell's name as caption), completion at complete_tick.
func skill_effect_contracts() -> void:
	var cutin = BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var events: Array[String] = []
	cutin.released.connect(func(_s, _a, _d, _c): events.append("release"))
	cutin.impact.connect(func(_s, _a, _d, _c): events.append("impact"))
	var rows: Dictionary = cutin.skill_effects.manifest["rows"]
	var caster := unit("001")
	var target := unit("021")
	var played := 0
	for skill_id in rows:
		if rows[skill_id]["presentation"] != "script" or rows[skill_id]["channel"] != "special":
			continue
		for hit in [true, false]:
			events.clear()
			var strike := {"skill_id": skill_id, "skill_name": str(rows[skill_id]["name"]), "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": hit, "damage": 9 if hit else 0, "defender_hp_before": 22, "defender_hp_after": 13 if hit else 22, "attacker_before": {}, "defender_before": {}}
			cutin.play(strike, caster, target, false)
			var frames := 0
			var objects_seen := false
			var untitled_before_result := true
			var result_shown := false
			var lead_shot := true
			var timeline: Dictionary = {}
			# 001's s_action cast lead (140 ticks: banner over the shadowed map, insets, portrait)
			# precedes the attack script; it replaces the 30-tick stand-in of an empty attack script.
			var lead: Dictionary = cutin.cast_lead(cutin.clips[0])
			var lead_ticks := int(lead["complete_tick"])
			while cutin.busy() and frames < 2000:
				frames += 1
				cutin._process(TICK)
				if not cutin.busy(): break
				if timeline.is_empty(): timeline = cutin.clips[0]["effect_timeline"]
				var tick: int = frames - lead_ticks + (int(cutin.skill_effects.EMPTY_ATTACK_LEAD_TICKS) if bool(timeline["empty_attack"]) else 0)  # the script's own clock, one tick per 16 ms step
				if frames < lead_ticks and (cutin.scenery.visible or cutin.vitals.visible or cutin.stage.size != Vector2(640, 480) or not cutin.attacker_sprite.visible or not cutin.attacker_sprite.texture.resource_path.ends_with("001/special-0.png") or cutin.result.visible): lead_shot = false
				if tick < int(timeline["result_tick"]) and cutin.result.visible: untitled_before_result = false
				if tick > int(timeline["result_tick"]) and cutin.result.visible and cutin.result.position.y == 264 and RuntimeReadback.result_text(cutin) == ("9" if hit else BattleCombatCutin.MISS_TEXT): result_shown = true
				if cutin.skill_effects.sprites.any(func(sprite): return sprite.visible): objects_seen = true
			var expected_frames: int = cutin.skill_effects.clip_complete_tick(timeline, cutin.result_spawns(strike)) + lead_ticks - (int(cutin.skill_effects.EMPTY_ATTACK_LEAD_TICKS) if bool(timeline["empty_attack"]) else 0)
			check(lead_ticks == 140 and lead_shot, "%s hit=%s opens with 001's 140-tick cast lead: banner P001_201 over the map shot, no backdrop or vitals (%s)" % [skill_id, str(hit), str(lead_shot)])
			check(not cutin.busy() and frames < 2000 and absi(frames - expected_frames - 1) <= 1, "%s hit=%s completes at its cast lead + clip_complete_tick, ±1 frame of float accumulation (frames=%d expected=%d)" % [skill_id, str(hit), frames, expected_frames])
			check(events == ["release", "impact"], "%s hit=%s fires one release then one impact (%s)" % [skill_id, str(hit), str(events)])
			check(objects_seen and untitled_before_result and result_shown, "%s hit=%s draws script objects, shows no name caption before the result, then the result line: the number／MISS alone, no skill-name head (UI6) (%s %s %s)" % [skill_id, str(hit), str(objects_seen), str(untitled_before_result), str(result_shown)])
			check(timeline["unimplemented"].is_empty() and timeline["instructions"] > 0, "%s compiled every instruction" % skill_id)
			played += 1
	check(played == 116, "58 script rows × hit／miss played through the cut-in (%d)" % played)
	var cast := 0
	for skill_id in rows:
		if rows[skill_id]["channel"] != "magic":
			continue
		events.clear()
		var strike := {"skill_id": skill_id, "magic_key": "x", "magic_name": str(rows[skill_id]["name"]), "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
		cutin.play(strike, caster, target, false, Vector2(470, 320), Vector2(190, 210), [Vector2(470, 320), Vector2(430, 300)])
		var frames := 0
		var objects_seen := false
		var map_shot := true
		var timeline: Dictionary = {}
		while cutin.busy() and frames < 6000:
			frames += 1
			cutin._process(TICK)
			if not cutin.busy(): break
			timeline = cutin.clips[0]["effect_timeline"]
			if cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and str(sprite.texture.resource_path).contains("skill_effects/frames/")): objects_seen = true
			if cutin.scenery.visible or cutin.vitals.visible or cutin.attacker_sprite.visible or cutin.defender_sprite.visible or cutin.stage.size != Vector2(640, 480) or cutin.result.visible: map_shot = false
		# An effect_caster adds its wait: N + 2 calls — the call that builds the caster object
		# (0x442f77) and the one that finds +0x9e at 0 and sets 0x19／7 (0x442fe2／0x442cd0), around
		# the N calls that count +0x9e down (0x442fc7) — and Local's one call more before the lead
		# (0x14 sets 0x15 and returns, 0x442f35). No battle camera here, so the state 0 glide to the
		# caster, the Global glide to the effect centre and the receiver glides take no time.
		var caster_wait := 0 if not timeline.has("caster") else int(timeline["caster"]["ticks"]) + 2 + (0 if bool(timeline["global"]) else 1)
		var expected := int(ceil(cutin.Timing.CAST_LEAD_IN / cutin.Timing.PLAYBACK_SPEED / TICK)) + caster_wait + int(timeline["complete_tick"])
		check(not cutin.busy() and frames < 6000 and absi(frames - expected) <= 2, "%s completes at its cast lead + effect_caster wait + complete_tick (frames=%d expected=%d)" % [skill_id, frames, expected])
		check(events == ["release", "impact"] and objects_seen and map_shot, "%s fires one release then one impact, draws its script objects on the map shot without a name caption (%s %s %s)" % [skill_id, str(events), str(objects_seen), str(map_shot)])
		cast += 1
	check(cast == 39, "39 magic rows played through the cut-in (%d)" % cast)
	# 天雷猛襲劍 shows its own SP00_003 panel while the caster's shot runs, then the darkened backdrop.
	cutin.play({"skill_id": "special:magicAIR:magicCode01", "skill_name": "天雷猛襲劍", "attacker_id": "a", "defender_id": "b", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}, caster, target, false)
	var backdrops: Array[String] = []
	while cutin.busy():
		cutin._process(TICK)
		if cutin.busy() and cutin.scenery.visible and (backdrops.is_empty() or backdrops.back() != cutin.scenery.texture.resource_path):
			backdrops.append(cutin.scenery.texture.resource_path)
	check(backdrops.size() == 2 and backdrops[0].ends_with("skill_effects/frames/sp00_003.shp.png") and backdrops[1] == str(cutin.manifest["background"]["res_path"]), "天雷猛襲劍 backdrops after the cast lead: its SP00_003 panel, then the battle backdrop (%s)" % str(backdrops))
	# A caster outside the combat-animation packet (authored 102: its row is in battle200's table, not
	# this chapter-01 one; every chapter-01 on-field actor has a row since CUTIN069) still
	# plays the script: backdrop, objects and every sound, the landing BOMB0017 included; only its
	# close-up is left out. The text-only missing-art clip (0.75 s, silent) is for ordinary strikes.
	var outsider := caster.duplicate(true)
	outsider["actor_id"] = "102"
	check(not cutin.manifest["actors"].has("102"), "102 has no chapter-01 combat-animation row (fixture premise)")
	cutin.play({"skill_id": "special:magicOTHER:magicCode01", "skill_name": "氣刃斬", "attacker_id": "a", "defender_id": "b", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}, outsider, target, false)
	var bare_frames := 0
	var bare_attacker_seen := false
	var bare_timeline: Dictionary = {}
	var bare_played: Array = []
	while cutin.busy() and bare_frames < 2000:
		bare_frames += 1
		cutin._process(TICK)
		if not cutin.busy(): break
		bare_timeline = cutin.clips[0].get("effect_timeline", {})
		bare_played = cutin.clips[0].get("effect_sounds_played", [])
		if cutin.attacker_sprite.visible: bare_attacker_seen = true
	var bare_members: Array = bare_played.map(func(index): return bare_timeline["events"][index]["member"])
	check(not bare_timeline.is_empty() and bare_members.has("WAV\\SP01-001.WAV") and bare_members.has("WAV\\BOMB0017.WAV") and bare_played.size() == bare_timeline["events"].filter(func(event): return event["kind"] == "sound").size(), "an art-less caster's 氣刃斬 plays its script and every sound, the landing BOMB0017 included (%s)" % str(bare_members))
	check(not bare_attacker_seen and bare_frames > 150, "…with the caster's close-up left out, for the script's length (%d frames)" % bare_frames)
	# Rows outside the player keep their routes: a strike without a skill_id borrows 氣刃斬,
	# the dedicated rows are not `script`.
	check(cutin.skill_effects.presentation("") == "" and cutin.skill_effects.presentation("special:magicMIND:magicCode03") == "dedicated_module" and cutin.skill_effects.presentation("special:magicOTHER:magicCode06") == "dedicated_module", "presentation lookup: unknown id → borrowed staging, 毒魔箭／月花圓舞 → dedicated modules")
	cutin.play({"skill_name": "連續突刺", "damage": 6, "hit": true, "defender_hp_before": 22, "defender_hp_after": 16, "attacker_before": {}, "defender_before": {}}, caster, target, false)
	cutin._process(1.0 / 60.0)
	check(cutin.clips[0]["presenter"] == null and not cutin.clips[0].has("effect_timeline") and cutin.blade.visible, "a strike without a skill_id matches no presenter and keeps the borrowed 氣刃斬 blade staging")
	while cutin.busy(): cutin._process(1.0 / 60.0)
	# Support specials carry no damage: the result line shows the recovery (the number／cure label),
	# never "0". Original: 0x4084e0 kind 2／3 → green／blue NUM digits, no sign glyph and no HP／MP
	# suffix (UI6); the typed parts carry the kind both the map and the cut-in line colour by.
	var heal := {"skill_id": "special:magicWATER:magicCode02", "skill_name": "萬息集氣法", "special_key": "special_support", "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 0, "actual_damage": 0, "healing": 27, "restored_mp": 0, "support_effects": [], "defender_hp_before": 13, "defender_hp_after": 40, "attacker_before": {}, "defender_before": {}}
	check(BattleCombatCutin.strike_feedback(heal) == "27", "a special heal receipt reads as its healed amount alone (%s)" % BattleCombatCutin.strike_feedback(heal))
	check(BattleCombatCutin.feedback_parts(heal) == [{"text": "27", "kind": "heal"}], "the heal part carries the green NUM2xx kind and no HP suffix")
	var mixed := heal.duplicate(true)
	mixed.merge({"skill_id": "special:magicWATER:magicCode04", "skill_name": "萬息臨界法", "restored_mp": 12}, true)
	check(BattleCombatCutin.strike_feedback(mixed) == "27 · 12", "HP and MP recovery both show, numbers only (%s)" % BattleCombatCutin.strike_feedback(mixed))
	check(BattleCombatCutin.feedback_parts(mixed).map(func(part): return part["kind"]) == ["heal", "mp"], "HP then MP, as the original stacks the blue MP number above the green HP number")
	var cure := heal.duplicate(true)
	cure.merge({"skill_id": "special:magicWATER:magicCode03", "skill_name": "萬息秘孔術", "healing": 0, "defender_hp_after": 13, "support_effects": [{"status": "poison", "removed": true}, {"status": "no_magic", "removed": false}]}, true)
	check(BattleCombatCutin.strike_feedback(cure) == "解毒 · 無禁魔", "a cure receipt names the removed and absent statuses (%s)" % BattleCombatCutin.strike_feedback(cure))
	var idle := heal.duplicate(true)
	idle.merge({"hit": false, "healing": 0, "defender_hp_after": 13}, true)
	check(BattleCombatCutin.strike_feedback(idle) == "未回復" and BattleCombatCutin.support_feedback_parts(idle) == ["未回復"], "a support receipt that restored nothing reads 未回復, not MISS or 0")
	check(BattleCombatCutin.feedback_parts({"actual_damage": 12, "status_effects": []}) == [{"text": "12", "kind": "damage"}], "a damage result is one unsigned red part; a non-support result adds no 未回復")
	# Sampled when the number first shows: 0x404643 spawns it at aniShowHitResult and deletes it
	# after its life (34 ＋ 10×digits ticks) while the shot runs on to the script's end — the
	# objcomd.txt tracks of 萬息集氣法's objects outlast it — so the last busy frame shows none.
	cutin.play(heal, caster, target, false)
	var heal_result := ""
	while cutin.busy():
		cutin._process(1.0 / 60.0)
		if heal_result == "" and cutin.busy() and cutin.result.position.y == 264: heal_result = RuntimeReadback.result_text(cutin)
	check(heal_result == "27", "the scripted special heal cut-in shows the healed amount alone at aniShowHitResult, no skill-name head or HP suffix (UI6) (%s)" % heal_result)
	# Stat-buff specials (千羽風靈壁／激怒／精神統一) carry damage 0 and stat_effects: 0x404643 shows no
	# number for a zero HP／MP change, so the line names each buff (power · turns) as the map does.
	var focus := {"skill_id": "special:magicMIND:magicCode01", "skill_name": "精神統一", "special_key": "special_stat", "attacker_id": "leonard", "defender_id": "leonard", "hit": true, "damage": 0, "actual_damage": 0, "defender_hp_before": 13, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {},
		"stat_effects": [{"kind": "defense_up", "before_word": 0, "after_word": (12 << 16) | 3, "before_power": 0, "after_power": 12, "duration": 3}, {"kind": "attack_up", "before_word": 0, "after_word": (9 << 16) | 4, "before_power": 0, "after_power": 9, "duration": 4}]}
	check(BattleCombatCutin.strike_feedback(focus) == "防禦 +12 · 3回 · 攻擊 +9 · 4回", "a special buff receipt names its buffs in native order, not 0 (%s)" % BattleCombatCutin.strike_feedback(focus))
	check(BattleCombatCutin.feedback_parts(focus).map(func(part): return part["kind"]) == ["caption", "caption"], "buff parts are uncoloured captions (no defProcShowNumber digit set)")
	var dispel := focus.duplicate(true)
	dispel["stat_effects"] = [{"kind": "attack_up", "before_word": (9 << 16) | 4, "after_word": 0, "before_power": 9, "after_power": 0, "duration": 0}]
	check(BattleCombatCutin.strike_feedback(dispel) == "攻擊增益解除", "a cleared buff word reads as its dispel (%s)" % BattleCombatCutin.strike_feedback(dispel))
	var untaken := focus.duplicate(true)
	untaken.merge({"hit": false, "stat_effects": []}, true)
	check(BattleCombatCutin.strike_feedback(untaken) == "MISS", "a stat receipt where nothing took reads as the miss (0x404643 kind 5, NUM513 MISS), not 0 or empty")
	cutin.play(focus, caster, caster, false)
	# The buff captions have no original glyph: OPT-INFO=公開 only.
	cutin.captions_public = true
	var focus_result := ""
	while cutin.busy():
		cutin._process(1.0 / 60.0)
		# Read while the line shows: the close (0x404ada) leaves the cut-in for the map lighten.
		if cutin.busy() and cutin.result.visible and cutin.result.position.y == 264: focus_result = cutin.result.text
	check(focus_result == "防禦 +12 · 3回 · 攻擊 +9 · 4回", "the scripted special buff cut-in shows the buffs at aniShowHitResult, no skill-name head (UI6) (%s)" % focus_result)
	cutin.free()


func sprite_key_contracts() -> void:
	var Key = preload("res://game/battle/runtime/ActorSpriteKey.gd")
	var shared: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Key.SHARED_WALK_MANIFEST_PATH))
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/battle037/actor_walk_frames/actor_walk_manifest.json"))
	var portraits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/portraits/manifest.json"))["actors"]
	check(shared["schema"] == "hsl_actor_walk_manifest.v1" and shared["actors"].keys().size() == 11, "shared up-title manifest keeps the walk manifest schema with 010–017/019/020 + 052")
	for row in ["010", "011", "012", "013", "014", "015", "016", "017", "019", "020", "052"]:
		check(int(shared["actors"][row]["frame_count"]) == 30 and str(shared["actors"][row]["frames"][0]["res_path"]).begins_with("res://content/imported/hsl/shared/actor_walk_frames/%s/" % row), "shared row %s carries its 30 frames under the shared directory" % row)
	check(not shared["actors"].has("018"), "018 (SHAPEDEF row commented out in the original) is not imported")
	var leonard_up := {"actor_id": "001", "job_up_target_actor_id": "010", "job_up_history": [{}]}
	check(Key.resolve(leonard_up) == "010" and Key.resolve({"actor_id": "001"}) == "001", "resolve prefers the job-up target row, else the actor id")
	check(Key.frame_key(leonard_up, [level, shared]) == "010", "010 walk frames come from the shared manifest when the level manifest lacks them")
	check(Key.manifest_entry("010", [level, shared]) == shared["actors"]["010"], "lookup order: level manifest, then shared")
	check(Key.manifest_entry("001", [level, shared]) == level["actors"]["001"] and Key.manifest_entry("001", [level, shared]) != shared.get("actors", {}).get("001", {}), "a row the level manifest has is served from the level manifest")
	var fake_level := {"actors": {"010": {"actor_id": "010", "frames": [], "marker": "level"}}}
	check(Key.manifest_entry("010", [fake_level, shared]).get("marker", "") == "level", "the level manifest wins over the shared one for the same row")
	check(Key.manifest_entry("999", [level, shared]).is_empty(), "an unknown row resolves to no entry (runtime falls back to its single frame)")
	check(Key.frame_key({"actor_id": "009", "job_up_target_actor_id": "018"}, [level, shared]) == "009", "018 without frames keeps the 009 base walk frames")
	check(Key.frame_key({"actor_id": "008", "job_up_target_actor_id": "052"}, [level, shared]) == "052", "052 (level-37 in-battle job-up) resolves to the shared frames")
	check(Key.frame_key({"actor_id": "003"}, [level, shared]) == "003", "a member without job-up keeps its own row")
	check(Key.row_key({"actor_id": "002", "job_up_target_actor_id": "020"}, portraits) == "020" and str(portraits["020"]["source_member"]) == "SHAPE\\FACE0020.SHP", "緹娜 020 公主 shows FACE0020 (own portrait row)")
	check(Key.row_key(leonard_up, portraits) == "001", "010–019 repeat the base FACE: the base portrait row serves them")
	check(Key.row_key({"actor_id": "002"}, portraits) == "002", "no job-up: own portrait row")
	var vitals = preload("res://game/battle/scene/BattleVitals.gd").new()
	root.add_child(vitals)
	var tina := unit("001")  # the first battle fields no 002; the panel only reads the row keys and vitals
	tina["actor_id"] = "002"
	vitals.show_unit(tina)
	check(vitals.portrait.texture.resource_path.ends_with("portraits/002.png") and vitals.values["role"].text == "祭司", "base 緹娜: FACE0001 portrait and her base title")
	tina["job_up_target_actor_id"] = "020"
	vitals.show_unit(tina)
	check(vitals.portrait.texture.resource_path.ends_with("portraits/020.png") and vitals.values["name"].text == "緹娜" and vitals.values["role"].text == "公主", "020 緹娜: FACE0020 portrait, same name, the target row's title")
	var leonard := unit("001")
	leonard["job_up_target_actor_id"] = "010"
	vitals.show_unit(leonard)
	check(vitals.portrait.texture.resource_path.ends_with("portraits/001.png") and vitals.values["role"].text == "劍豪", "010 雷歐納德: base portrait (same FACE0000), the 劍豪 title")
	vitals.free()


## BattleVitals.mask — the three 0x434d10 predicates on every WINDOW10／WINDOW20 surface
## and the cut-in strip: unknown (known byte clear) → ?? level, ??? exp／HP／MP／name／state／
## resists; no_attack template bit (0x446b00) → the same without HP; template level > 99 →
## ?? level only. The first battle fields no no_attack or level>99 unit: fixtures.
func identity_mask_contracts() -> void:
	var Vitals = preload("res://game/battle/scene/BattleVitals.gd")
	var vitals = Vitals.new()
	root.add_child(vitals)
	var enemy := unit("021")
	check(Vitals.mask(enemy, false) == {"hp": true, "identity": true, "level": true}, "known byte clear masks HP, identity and level")
	check(Vitals.mask(enemy, true) == {"hp": false, "identity": false, "level": false}, "a fought ordinary unit shows everything")
	var pacifist := unit("021")
	pacifist["no_attack"] = true
	check(Vitals.mask(pacifist, true) == {"hp": false, "identity": true, "level": true}, "no_attack masks identity and level but never HP (0x434d10 HP row tests bVar22 alone)")
	var veteran := unit("021")
	veteran["level"] = 100
	check(Vitals.mask(veteran, true) == {"hp": false, "identity": false, "level": true}, "level above 99 masks the level alone")
	vitals.show_unit(pacifist, -1, true)
	check(vitals.values["hp"].text == "%d/%d" % [int(pacifist["hp"]), int(pacifist["max_hp"])] and vitals.hp_bar.value > 0, "a known no_attack unit keeps its HP readable")
	check(vitals.values["level"].text == "??" and vitals.values["exp"].text == "???" and vitals.values["mp"].text == "???" and vitals.values["name"].text == "???" and vitals.values["state"].text == "???", "a no_attack unit prints ?? level and ??? exp／MP／name／state")
	check(vitals.resist_values.all(func(label): return label.text.ends_with("???")) and vitals.values["role"].text != "???" and vitals.values["race"].text != "???", "no_attack masks the resists, 稱號 and 種族 stay readable")
	vitals.show_unit(veteran, -1, true)
	check(vitals.values["level"].text == "??" and vitals.values["exp"].text != "???" and vitals.values["hp"].text != "???" and vitals.values["mp"].text != "???", "a level-100 unit prints ?? for the level and everything else in the clear (021's name is 306 ???)")
	vitals.show_unit(enemy, -1, false)
	check(vitals.values["hp"].text == "???" and vitals.values["mp"].text == "???" and vitals.values["level"].text == "??" and vitals.hp_bar.value == 100, "the unknown strip: ??? everywhere, a full-health unit shows a full HP bar")
	var wounded := unit("026")
	wounded["hp"] = int(wounded["max_hp"]) / 2
	wounded["mp"] = int(wounded.get("max_mp", 0)) / 2
	vitals.show_unit(wounded, -1, false)
	check(vitals.values["hp"].text == "???" and vitals.values["mp"].text == "???" and absf(vitals.hp_bar.value - 100.0 * float(wounded["hp"]) / float(wounded["max_hp"])) < 1.0 and absf(vitals.mp_bar.value - 100.0 * float(wounded["mp"]) / float(wounded["max_mp"])) < 1.0, "an unknown wounded unit keeps the real HP／MP bar ratio behind ??? (0x4364e0 reads +0xd8/+0xdc without the known byte)")
	vitals.show_unit(wounded, 5, false)
	check(absf(vitals.hp_bar.value - 500.0 / float(wounded["max_hp"])) < 1.0, "the visible-HP override drives the masked bar too (bar step 1)")
	var pacifist_mage := unit("026")
	pacifist_mage["no_attack"] = true
	pacifist_mage["mp"] = int(pacifist_mage["max_mp"]) / 2
	vitals.show_unit(pacifist_mage, -1, true)
	check(vitals.values["mp"].text == "???" and absf(vitals.mp_bar.value - 100.0 * float(pacifist_mage["mp"]) / float(pacifist_mage["max_mp"])) < 1.0, "a no_attack unit's MP bar keeps its ratio behind ???")
	vitals.free()
	# WINDOW20: the same mask on the status page's strip and attribute rows; the equipment
	# list is not in the masked text (0x434d10 item rows carry no bVar test).
	var panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	root.add_child(panel)
	panel.show_unit(enemy, false)
	check(panel.vitals.values["hp"].text == "???" and panel.vitals.values["name"].text == "???", "the status page of an unknown enemy masks its strip")
	check(panel.stat_values.values().all(func(label): return label.text == "???"), "the status page of an unknown enemy masks 力量／反應／精神／體質／攻擊力／防禦力／魔擊力／敏捷度／移動力")
	check(panel.equipment_labels["weapon"].text != "???" and not panel.permanent_summary.visible, "equipment stays readable; the remake's permanent summary hides with the identity")
	panel.show_unit(pacifist, true)
	check(panel.vitals.values["hp"].text != "???" and panel.stat_values["str"].text == "???", "a no_attack unit's status page keeps HP and masks the attribute rows")
	panel.show_unit(enemy, true)
	check(panel.stat_values["str"].text != "???" and panel.vitals.values["hp"].text != "???", "a fought enemy's status page is in the clear")
	panel.free()
	# Cut-in strip: the shot of a defender the player has not fought (a friendly AI's weapon
	# hit) masks the same way; the attacker's own strip is a player unit, in the clear.
	var cutin = BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var strike := {"hit": true, "damage": 5, "defender_hp_before": 22, "defender_hp_after": 17, "attacker_id": "actor023_1", "defender_id": "actor021_1"}
	var friend := unit("023")
	cutin.play(strike, friend, enemy, false, Vector2(320, 240), Vector2(240, 240), [], [], {str(friend["id"]): true, str(enemy["id"]): false})
	cutin._show_shot(cutin.clips[0], false)
	check(cutin.vitals.values["hp"].text == "%d/%d" % [int(friend["hp"]), int(friend["max_hp"])], "the attacker shot of a known unit shows its HP")
	cutin._show_shot(cutin.clips[0], true)
	check(cutin.vitals.values["hp"].text == "???" and cutin.vitals.values["name"].text == "???" and cutin.vitals.values["role"].text != "???", "the victim shot of an enemy the player has not fought masks HP and name, keeps 稱號")
	cutin.clips[0]["impact_emitted"] = true
	cutin._show_shot(cutin.clips[0], true)
	check(cutin.vitals.values["hp"].text == "???", "the mask persists after the hit: an AI weapon hit does not reveal the unit")
	cutin.clips.clear()
	cutin.play(strike, unit("001"), enemy, false)
	cutin._show_shot(cutin.clips[0], true)
	check(cutin.vitals.values["hp"].text == "22/22", "a clip enqueued without a known map shows the strip in the clear (the player's own target is known at confirmation)")
	cutin.queue_free()


func inventory_contracts() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var player: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	var ally: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "enemy023_1")
	var foe: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	ally["coord"] = player["coord"] + Vector2i.RIGHT
	foe["coord"] = player["coord"] + Vector2i.LEFT
	player["hp"] = 10
	scene.apply_loop(scene.play_loop, "test")
	var before: Dictionary = scene.play_loop.duplicate(true)
	var session: Dictionary = BattlePlayLoop.begin_give(before)
	var received: Dictionary = BattlePlayLoop.confirm_give(session, ally["id"], 0, 241, -1, 0, session["item_revision"])
	var given: Dictionary = BattlePlayLoop.finish_give(received, received["item_revision"])
	check(BattlePlayLoop.unit(given, "leonard")["inventory"].count(241) == 2, "give decrements the owner exactly once")
	check(BattlePlayLoop.unit(given, ally["id"])["inventory"].count(241) == 1, "give adds the same item to the selected ally")
	check(BattlePlayLoop.confirm_give(given, ally["id"], 0, 241, -1, 0, session["item_revision"]) == given, "give cannot replay after the action handoff")
	check(BattlePlayLoop.confirm_give(session, foe["id"], 0, 241, -1, 0, session["item_revision"]) == session, "enemy transfer must be inert")
	check(BattlePlayLoop.confirm_give(session, "leonard", 0, 241, -1, 0, session["item_revision"]) == session, "self transfer cannot spend an action")
	check(BattlePlayLoop.discard_item(before, "missing") == before, "unknown inventory entry must not create or delete items")
	check(scene.play_loop == before, "inventory rules must not mutate their input")
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("UseCommand").pressed.emit()
	scene.item_panel.rows.get_child(0).pressed.emit()
	check(scene.item_panel.page == "target", "selection must precede recipient confirmation")
	scene.item_panel.cancel()
	# 0x444a5c..0x444a94: the cancelled use pick puts the held item back first-empty (0x436e30),
	# the end of the compacted bag, and reopens the use window without spending the action.
	var use_cancelled: Dictionary = scene.play_loop.duplicate(true)
	var bag_start: Array = BattlePlayLoop.unit(before, "leonard")["inventory"].filter(func(code): return int(code) != 0)
	var bag_use_cancelled: Array = BattlePlayLoop.unit(use_cancelled, "leonard")["inventory"].filter(func(code): return int(code) != 0)
	check(scene.item_panel.page == "inventory" and bag_use_cancelled == bag_start.slice(1) + bag_start.slice(0, 1) and use_cancelled["turn_queue"] == before["turn_queue"] and BattlePlayLoop.unit(use_cancelled, "leonard")["hp"] == 10, "target cancellation returns the item to the end of the bag and reopens the inventory without spending")
	scene.menus.use_inventory_item("241", "leonard")
	check(scene.play_loop == use_cancelled, "stale target callback cannot heal after cancellation")
	scene.item_panel.cancel()
	check(scene.item_panel.page == "commands", "nested cancel returns to the item submenu")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("DropCommand").pressed.emit()
	scene.item_panel.rows.get_child(0).pressed.emit()
	scene.item_panel.cancel()
	# 0x436e80 then 0x436e30: the cancelled pick goes back first-empty, the end of the compacted bag.
	var put_back: Dictionary = scene.play_loop.duplicate(true)
	var bag_before: Array = BattlePlayLoop.unit(use_cancelled, "leonard")["inventory"].filter(func(code): return int(code) != 0)
	var bag_after: Array = BattlePlayLoop.unit(put_back, "leonard")["inventory"].filter(func(code): return int(code) != 0)
	check(bag_after == bag_before.slice(1) + bag_before.slice(0, 1), "a cancelled drop pick goes back to the end of the bag")
	scene.menus.discard_inventory_item("241")
	check(scene.play_loop == put_back, "cancelled discard callback cannot consume an item")
	scene.item_panel.rows.get_child(0).pressed.emit()
	scene.item_panel.drop_button.pressed.emit()
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"].count(241) == 2, "discard updates the real inventory")
	check(scene.play_loop["turn_queue"] == before["turn_queue"] and not scene.ai_playback_active, "discard confirmation keeps player control")
	var after: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.discard_inventory_item("241")
	check(scene.play_loop == after, "repeated closed-panel confirmation must be inert")
	scene.queue_free()
	await process_frame


## Map overlays across a cast (lane P5, docs/evidence_packets/static_reverse/original_cast_overlays.md):
## a player's confirmed special or magic draws no range／area cells, cursor, identity strip
## or hit preview from the confirm frame on — its presentation starts on that frame, with no
## BattleAttackCue re-drawing the range; an AI cast keeps the cue (range, cursor, target hold)
## and still clears it before its effect plays.
func cast_overlay_contracts() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	var player: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	var enemy: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	enemy["hp"] = 100
	enemy["max_hp"] = 100
	player["stamina"] = 20
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command("special")
	scene.magic_panel.choices["special:magicOTHER:magicCode01"].pressed.emit()
	scene._process(0)
	var attack_cells: Array = scene.move_overlay.get_children().filter(func(child): return str(child.name).begins_with("AttackCell"))
	check(scene.interaction_state == "attack_select" and scene.move_overlay.visible and not attack_cells.is_empty(), "special target select draws its range cells")
	scene.attack_selected_coord(enemy["coord"])
	check(scene.play_loop.get("last_combat", {}).has("skill_id"), "fixture settles a real special receipt")
	scene._process(0)
	attack_cells = scene.move_overlay.get_children().filter(func(child): return str(child.name).begins_with("AttackCell"))
	check(not view.attack_cue.visible and view.cutin.busy(), "a player's confirmed special enters its presentation on the confirm frame, without the attack cue")
	check(not (scene.move_overlay.visible and not attack_cells.is_empty()) and not view.selection_cursor.visible and not view.target_vitals.visible and not view.combat_label.visible and not scene.action_menu.visible, "no range cells, cursor, identity strip, hit preview or menu while the player's cast plays")
	while view.cutin.busy(): view.cutin._process(100)
	for _job in range(12):
		if not view.combat_busy(scene.play_loop): break
		scene._process(1.0)
	scene.flush_ai_playback()
	scene.queue_free()
	await process_frame
	# AI cast: the fixture mage's own spell at an adjacent 雷歐納德, settled by the shared seam.
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var caster: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy026_1")
	caster["mp"] = caster["max_mp"]
	var leonard: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard")
	leonard["coord"] = caster["coord"] + Vector2i.RIGHT
	leonard["hp"] = 200
	leonard["max_hp"] = 200
	var spell := "magic:magicAIR:magicCode01"
	var receipt: Dictionary = BattleLoopCombat.resolve_skill(loop, caster["id"], "leonard", spell, BattlePlayLoop.skill_fields(loop, spell), caster["coord"], func(_n): return 0)
	check(receipt.has("skill_id") and not bool(caster.get("player_commandable", false)), "fixture settles a real AI cast receipt")
	# The lead-in's camera stage (0x43bf30 to the actor) is empty when the view already frames it.
	scene.center_camera_on_grid(caster["coord"])
	scene.apply_loop(loop, "test")
	scene._process(0)
	check(view.attack_cue.visible and view.attack_cue.stage() == "range" and not view.cutin.busy(), "an AI cast opens with the attack cue's range stage")
	scene._process(view.attack_cue.duration)
	check(not view.attack_cue.visible and view.cutin.busy(), "the AI cue clears before the cast presentation plays")
	scene.queue_free()
	await process_frame


## Lead-in beats (lane P6, docs/evidence_packets/static_reverse/original_cast_overlays.md): the
## player's confirmed normal attack enters its cut-in on the confirm frame (0x50 → 0x51 → 0x52
## draw nothing); the AI lead-in runs the original's tick counts — attack 6-tick range, glide,
## 12-tick target; cast 24-tick range, glide, 24-tick hold — with the glide stepped per tick
## by 0x45e882, so its length follows the distance; an AI cast captions only the lead-in with
## the skill name at the screen-centred y=276 (0x43e110), and neither the cut-in nor the map
## effect repeats it before the result.
func lead_in_contracts() -> void:
	const BattleAttackCue = preload("res://game/battle/scene/BattleAttackCue.gd")
	# Glide tick counts of the original machine code, emulated off-line from the EXE tables
	# (cell deltas × 32 px → calls of 0x45e882 up to and including the arrival tick).
	var glide_ticks := {Vector2i(1, 0): 15, Vector2i(0, -1): 15, Vector2i(2, 0): 20, Vector2i(3, 0): 24, Vector2i(1, 1): 23, Vector2i(2, 1): 31, Vector2i(-3, -2): 22, Vector2i(5, 3): 39, Vector2i(4, -7): 35, Vector2i(12, 0): 42, Vector2i.ZERO: 1}
	for cells in glide_ticks:
		var path: Array[Vector2i] = BattleAttackCue.glide_path(Vector2i.ZERO, cells * 32)
		check(path.size() == glide_ticks[cells] and path.back() == cells * 32, "0x45e882 glide over %s cells takes %d ticks and ends on the target (%d)" % [str(cells), glide_ticks[cells], path.size()])
	check(BattleAttackCue.glide_path(Vector2i.ZERO, Vector2i(32, 0)) == [Vector2i(4, 0), Vector2i(7, 0), Vector2i(10, 0), Vector2i(12, 0), Vector2i(14, 0), Vector2i(16, 0), Vector2i(18, 0), Vector2i(20, 0), Vector2i(22, 0), Vector2i(24, 0), Vector2i(26, 0), Vector2i(28, 0), Vector2i(30, 0), Vector2i(32, 0), Vector2i(32, 0)], "one-cell glide: step distance>>3 clamped to 2..16, snap within 1 px")
	check(BattleAttackCue.glide_path(Vector2i.ZERO, Vector2i(-96, -64)).slice(0, 4) == [Vector2i(-12, -8), Vector2i(-22, -15), Vector2i(-32, -22), Vector2i(-40, -28)], "diagonal glide follows the 256-step direction table with arithmetic-shift truncation")
	# Player normal attack: confirm → cut-in, no lead-in.
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	var player: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	var enemy: Dictionary = BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	enemy["hp"] = 100
	enemy["max_hp"] = 100
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command("attack")
	scene._process(0)
	check(scene.interaction_state == "attack_select", "attack target select is open")
	# Target selection: the legal cell under the pointer carries the original's I_RECT01
	# yellow frame (user recording 178.0 s), not the move selection's corner brackets.
	scene.hovered_grid_cell = enemy["coord"]
	scene._process(0)
	check(view.selection_cursor.visible and view.selection_cursor.eligible and view.selection_cursor.target_frame, "the hovered legal target shows the I_RECT01 target frame")
	scene.attack_selected_coord(enemy["coord"])
	check(not scene.play_loop.get("last_combat", {}).is_empty() and not scene.play_loop["last_combat"].has("skill_id"), "fixture settles a real normal-attack receipt")
	scene._process(0)
	check(not view.attack_cue.visible and view.cutin.busy() and not view.attack_cue.caption_layer.visible, "a player's confirmed normal attack enters its cut-in on the confirm frame, without the attack cue")
	while view.cutin.busy(): view.cutin._process(100)
	for _job in range(12):
		if not view.combat_busy(scene.play_loop): break
		scene._process(1.0)
	scene.flush_ai_playback()
	scene.queue_free()
	await process_frame
	# AI normal attack, adjacent (glide 15 ticks): 6 range + 15 glide + 12 target.
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var attacker: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy021_1")
	var leonard: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard")
	leonard["coord"] = attacker["coord"] + Vector2i.RIGHT
	leonard["hp"] = 200
	leonard["max_hp"] = 200
	var receipt: Dictionary = BattleLoopCombat.resolve_exchange(loop, attacker["id"], "leonard", func(_n): return 0)
	check(not receipt.is_empty() and not receipt.has("skill_id"), "fixture settles a real AI attack receipt")
	# The lead-in's camera stage (0x43bf30 to the actor) is empty when the view already frames it.
	scene.center_camera_on_grid(attacker["coord"])
	scene.apply_loop(loop, "test")
	scene._process(0)
	var cue = view.attack_cue
	check(cue.visible and cue.range_ticks == 6 and cue.glide.size() == 15 and cue.target_ticks == 12 and is_equal_approx(cue.duration, (6 + 15 + 12) * TICK), "AI attack lead-in: 6-tick range, 15-tick one-cell glide, 12-tick target (%d %d %d)" % [cue.range_ticks, cue.glide.size(), cue.target_ticks])
	check(cue.caption == "" and not cue.caption_layer.visible, "an AI attack has no skill caption")
	scene._process(5.5 * TICK)
	check(cue.stage() == "range" and cue.cursor_position() == cue.source, "range holds with the cursor on the attacker for 6 ticks")
	scene._process(1.0 * TICK)
	check(cue.stage() == "cursor" and cue.cursor_position() == cue.source + Vector2(4, 0), "the 7th tick is the first glide step (4 px at 32 px distance)")
	scene._process(15.0 * TICK)
	check(cue.stage() == "target" and cue.cursor_position() == cue.target, "after the glide (arrival tick included) the cursor holds on the target")
	# The AI's cursor is the original's I_RECT01 cell frame — the player's target frame — and the
	# player's own selection cursor stays hidden even with the pointer resting on a cell.
	scene.hovered_grid_cell = leonard["coord"]
	scene._process(0)
	check(cue.TARGET_FRAME == view.selection_cursor.TARGET_FRAME and view.selection_cursor.target_frame_texture().get_size() == Vector2(32, 32), "the AI lead-in cursor draws the I_RECT01 target frame")
	check(not view.selection_cursor.visible, "no player selection cursor during the AI lead-in (interaction %s)" % scene.interaction_state)
	# Class check: show_selection is the player cursor's only show path; every interaction state
	# outside the player's targeting states (AI turns, menus, results, cutscenes) leaves it hidden.
	var cursor_probe: Dictionary = scene.play_loop.duplicate()
	for state in (load("res://game/sim/Interaction.gd") as Script).get_script_constant_map().values():
		if not (state is String) or state in Interaction.TARGETING:
			continue
		cursor_probe[LoopKeys.INTERACTION] = state
		view.show_selection(cursor_probe, leonard["coord"], scene.grid_cell_center_to_logical_position(leonard["coord"]), scene.grid_cell_size())
		check(not view.selection_cursor.visible, "no player selection cursor in interaction %s" % state)
	scene._process(11.0 * TICK)
	check(cue.visible and not view.cutin.busy(), "target holds 12 ticks before the cut-in")
	scene._process(1.0 * TICK)
	check(not cue.visible and view.cutin.busy(), "the AI attack cut-in starts when the 12-tick target hold ends")
	scene.queue_free()
	await process_frame
	# AI cast, two cells away (glide 20 ticks): 24 range + 20 glide + 24 hold, captioned.
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	loop = scene.play_loop.duplicate(true)
	var caster: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy026_1")
	caster["mp"] = caster["max_mp"]
	leonard = BattlePlayLoop.unit_ref(loop, "leonard")
	leonard["coord"] = caster["coord"] + Vector2i(2, 0)
	leonard["hp"] = 200
	leonard["max_hp"] = 200
	var spell := "magic:magicAIR:magicCode01"
	receipt = BattleLoopCombat.resolve_skill(loop, caster["id"], "leonard", spell, BattlePlayLoop.skill_fields(loop, spell), caster["coord"], func(_n): return 0)
	check(receipt.has("skill_id"), "fixture settles a real AI cast receipt two cells away")
	# The lead-in's camera stage (0x43bf30 to the actor) is empty when the view already frames it.
	scene.center_camera_on_grid(caster["coord"])
	scene.apply_loop(loop, "test")
	scene._process(0)
	cue = view.attack_cue
	var spell_name := str(receipt.get("magic_name", receipt.get("skill_name", "")))
	check(cue.visible and cue.range_ticks == 24 and cue.glide.size() == 20 and cue.target_ticks == 24 and is_equal_approx(cue.duration, (24 + 20 + 24) * TICK), "AI cast lead-in: 24-tick range, 20-tick two-cell glide, 24-tick hold (%d %d %d)" % [cue.range_ticks, cue.glide.size(), cue.target_ticks])
	check(spell_name != "" and cue.caption == spell_name and cue.caption_layer.visible and cue.caption_label.text == spell_name, "the AI cast captions its lead-in with the spell name (%s)" % spell_name)
	check(cue.caption_label.position.y == 276 and cue.caption_label.position.x == 0 and cue.caption_label.size.x == 640 and cue.caption_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "the caption is centred on the screen with its top at y=276, not at the top edge")
	scene._process(23.5 * TICK)
	check(cue.stage() == "range" and cue.caption_layer.visible, "range holds 24 ticks, captioned")
	scene._process(1.0 * TICK)
	check(cue.stage() == "cursor" and cue.caption_layer.visible, "the glide follows, captioned")
	scene._process(20.0 * TICK)
	check(cue.stage() == "target" and cue.cursor_position() == cue.target and cue.caption_layer.visible, "the 24-tick hold on the target, captioned")
	scene._process(22.5 * TICK)
	check(cue.visible and not view.cutin.busy(), "the hold lasts 24 ticks before the effect")
	scene._process(1.0 * TICK)
	check(not cue.visible and not cue.caption_layer.visible and view.cutin.busy(), "the caption leaves with the range when the cast presentation starts")
	view.cutin._process(0.1)
	check(not view.cutin.result.visible, "the cast presentation does not repeat the name caption at the top")
	scene.queue_free()
	await process_frame


## AI lead-in camera and area (lane R7-CUE, docs/evidence_packets/static_reverse/original_cast_overlays.md):
## the view first reaches the actor through the shared battle focus (0x43bf30; the no-move attack's
## sub-state 1) while nothing is drawn; a cast's glide frames the cursor every tick (0x43c0f0) and
## draws the effect area at the cursor's cell whether or not that cell is in range (0x4100e0),
## its hold keeps range＋area; an attack's glide carries the view by the cursor's step away from the
## far half-view bands (0x440233..0x44141d) and its target hold draws the cursor alone (0x44142a).
## Expected framings come from a second BattleCameraController (center_on_grid／center_on_point), so
## the assertions follow the shared focus point rather than a fixed screen position.
func ai_cue_camera_area_contracts() -> void:
	const BattleAttackCue = preload("res://game/battle/scene/BattleAttackCue.gd")
	const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
	var half := Vector2(320, 240)
	var world := Vector2(1600, 960)
	check(BattleAttackCue.edge_follow_request(Vector2(100, 100), Vector2(4, -3), half, world) == Vector2(4, -3), "a cursor short of the far bands carries the view on both axes, in either direction")
	check(BattleAttackCue.edge_follow_request(Vector2(1280, 100), Vector2(4, 2), half, world) == Vector2(0, 2), "x at map width − half view: no horizontal request")
	check(BattleAttackCue.edge_follow_request(Vector2(100, 720), Vector2(-4, 5), half, world) == Vector2(-4, 0), "y at map height − half view: no vertical request")
	check(BattleAttackCue.edge_follow_request(Vector2(-16, -16), Vector2(-4, -4), half, world) == Vector2.ZERO, "a negative coordinate requests only beyond the near half view (0x4413d7／0x44140e)")
	for kind in ["cast", "attack"]:
		var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
		scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
		root.add_child(scene)
		await process_frame
		scene.start_dev_first_control_harness()
		scene.set_process(false)
		var view = scene.get_node("BattlePresentation")
		view.cutin.set_process(false)
		var controller = scene.camera_controller
		var reference_camera := Camera2D.new()
		var reference = BattleCameraController.create(reference_camera, scene.map_config, controller.logical_viewport_size)
		var loop: Dictionary = scene.play_loop.duplicate(true)
		var actor: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy026_1" if kind == "cast" else "enemy021_1")
		var leonard: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard")
		if kind == "attack":
			# Mid-map, so the one-cell glide right stays short of the far half-view bands.
			var map_size: Vector2i = loop[LoopKeys.MAP_SIZE]
			actor["coord"] = Vector2i(map_size.x / 2 - 1, map_size.y / 2 - 1)
			for other in loop[LoopKeys.UNITS]:
				if other["id"] != actor["id"] and other["id"] != "leonard" and other["coord"] in [actor["coord"], actor["coord"] + Vector2i.RIGHT]:
					other["coord"] = Vector2i.ZERO
		leonard["coord"] = actor["coord"] + Vector2i(2, 0) if kind == "cast" else actor["coord"] + Vector2i.RIGHT
		leonard["hp"] = 200
		leonard["max_hp"] = 200
		var receipt: Dictionary
		var spell := "magic:magicAIR:magicCode01"
		if kind == "cast":
			actor["mp"] = actor["max_mp"]
			receipt = BattleLoopCombat.resolve_skill(loop, actor["id"], "leonard", spell, BattlePlayLoop.skill_fields(loop, spell), actor["coord"], func(_n): return 0)
		else:
			receipt = BattleLoopCombat.resolve_exchange(loop, actor["id"], "leonard", func(_n): return 0)
		check(not receipt.is_empty() and receipt.has("skill_id") == (kind == "cast"), "%s: fixture settles a real AI receipt" % kind)
		# Start with the view on the far corner: the lead-in first brings it to the actor.
		scene.center_camera_on_grid(Vector2i.ZERO)
		var start: Vector2 = scene.camera.position
		reference.center_on_grid(actor["coord"])
		var landing: Vector2 = reference_camera.position
		var camera_ticks: int = BattleCameraController.scroll_ticks(start, landing, BattleCameraController.BATTLE_SCROLL_STEP) - 1
		scene.apply_loop(loop, "test")
		scene._process(0)
		var cue = view.attack_cue
		check(camera_ticks > 0 and cue.camera_ticks == camera_ticks and cue.stage() == "camera", "%s: the lead-in opens with the camera stage of the shared focus glide to the actor (%d／%d ticks)" % [kind, cue.camera_ticks, camera_ticks])
		check(not cue.range_visible() and not cue.cursor_visible() and cue.area_rects().is_empty() and not cue.caption_layer.visible, "%s: the camera stage draws no range, cursor, area or caption" % kind)
		check(is_equal_approx(cue.duration, (camera_ticks + cue.range_ticks + cue.glide.size() + cue.target_ticks) * TICK), "%s: the camera stage lengthens the lead-in" % kind)
		scene._process((camera_ticks + 0.5) * TICK)
		check(cue.stage() == "range" and cue.range_visible() and cue.cursor_visible() and cue.cursor_position() == cue.source and cue.area_rects().is_empty(), "%s: the range stage draws the range and the cursor on the actor, no area" % kind)
		check(BattleCameraController.scroll_landed(Vector2i(scene.camera.position.round()), Vector2i(landing.round()), BattleCameraController.SCROLL_TOLERANCE), "%s: the view has reached the actor's framing (%s vs %s)" % [kind, scene.camera.position, landing])
		check(cue.caption_layer.visible == (kind == "cast"), "%s: only a cast captions its range stage" % kind)
		scene._process(cue.range_ticks * TICK)
		var range_cells: Array = BattlePlayLoop.strike_range_cells(loop, receipt)
		var fields: Dictionary = BattlePlayLoop.skill_fields(loop, spell)
		var area_outside_range := false
		var followed := true
		var areas_match := true
		# The focus glide lands during the range stage, so the glide starts from the landing.
		var previous: Vector2 = landing
		for index in range(cue.glide.size()):
			check(cue.stage() == "cursor" and cue.cursor_position() == cue.glide[index], "%s: glide tick %d" % [kind, index])
			var cursor: Vector2 = cue.glide[index]
			if kind == "cast":
				reference.center_on_point(cursor + scene.grid_cell_size() * 0.5)
				followed = followed and scene.camera.position == reference_camera.position
				var cell: Vector2i = scene.map_config.world_to_grid(cursor)
				var expected: Array = []
				for area_cell in BattlePlayLoop.SkillTargetRules.effect_cells(cell, fields, loop[LoopKeys.SKILL_TARGET_DATA], loop[LoopKeys.MAP_SIZE], actor["coord"]):
					expected.append(Rect2(scene.map_config.grid_to_world(area_cell), scene.grid_cell_size()))
				areas_match = areas_match and cue.area_rects() == expected and not expected.is_empty()
				area_outside_range = area_outside_range or (not range_cells.has(cell) and not cue.area_rects().is_empty())
			else:
				check(cursor.x < scene.map_config.world_size.x - 320 and cursor.y < scene.map_config.world_size.y - 240, "attack: the fixture glide stays short of the far bands")
				var step: Vector2 = cursor - (cue.source if index == 0 else cue.glide[index - 1])
				followed = followed and scene.camera.position == controller.clamped_position(previous + step)
				areas_match = areas_match and cue.area_rects().is_empty()
			previous = scene.camera.position
			scene._process(TICK)
		if kind == "cast":
			check(followed, "cast: every glide tick frames the cursor's point as center_on_point does, clamped to the map (0x43c0f0)")
			check(areas_match, "cast: every glide tick draws the effect area centred on the cursor's cell (0x4100e0 pixel >> 5)")
			check(range_cells.has(actor["coord"]) and not area_outside_range, "cast: the glide starts on the caster's own cell, itself a cast-range cell (0x40f8b0 mode -1 writes the origin), so every tick's area sits on the range")
		else:
			check(followed, "attack: every glide tick moves the view by the cursor's step, clamped (0x42dc50 → 0x46bede)")
			check(areas_match, "attack: an attack draws no effect area")
		var held: Vector2 = scene.camera.position
		check(cue.stage() == "target" and cue.cursor_visible(), "%s: the target hold follows the glide" % kind)
		if kind == "cast":
			check(cue.range_visible() and not cue.area_rects().is_empty() and cue.area_rects() == cue.glide_area.back(), "cast: the target hold draws range, area and cursor (0x441947)")
		else:
			check(not cue.range_visible() and cue.area_rects().is_empty(), "attack: the target hold draws the cursor alone (0x44142a has no 0x411480)")
		scene._process((cue.target_ticks - 1) * TICK)
		check(cue.stage() == "target" and scene.camera.position == held, "%s: the view holds during the target stage" % kind)
		reference_camera.free()
		scene.queue_free()
		await process_frame


## A script special over several receivers (風狼葬天擊's cross over three enemies) plays a clip per
## receiver in the receipt's order, the defense script's aniOver reopening the page for the next
## target (0x403d3d → 0x4104d0(1)): the cast lead and the attack page (its SP00_001 panel) on the
## first clip only, the close on the last only, each page's result its own receiver's damage. Each
## page's impact adds that receiver's number to the map, one at a time — with the close-up hidden
## (OPT-PACE 極快) too.
func area_special_contracts() -> void:
	const GameOptions = preload("res://game/settings/GameOptions.gd")
	const GameSettings = preload("res://game/settings/GameSettings.gd")
	var id := "special:magicAIR:magicCode02"
	for hidden in [false, true]:
		if hidden:
			var settings: Dictionary = GameSettings.load_settings()
			settings["presentation"] = {"OPT-PACE": BattleCombatCutin.Timing.PACE_HIDDEN_CUTIN}
			GameSettings._cache = settings
			GameOptions.environment_preset = GameOptions.PRESET_CUSTOM
		var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
		scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
		root.add_child(scene)
		await process_frame
		scene.start_dev_first_control_harness()
		scene.set_process(false)
		var view = scene.get_node("BattlePresentation")
		var cutin = view.cutin
		cutin.set_process(false)
		var loop: Dictionary = scene.play_loop
		var caster: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard")
		caster["stamina"] = 60
		TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"].append(id)
		# Three in a row two cells above 雷歐納德, the cross on the middle one; HP caps tell the damages apart.
		var row: Vector2i = caster["coord"] + Vector2i(0, -2)
		for entry in [["enemy021_1", Vector2i.LEFT, 1], ["enemy021_2", Vector2i.ZERO, 2], ["enemy021_3", Vector2i.RIGHT, 200]]:
			var enemy: Dictionary = BattlePlayLoop.unit_ref(loop, entry[0])
			enemy["coord"] = row + entry[1]
			enemy["hp"] = entry[2]
		var receipt := BattleLoopCombat.resolve_skill(loop, "leonard", "enemy021_2", id, BattlePlayLoop.skill_fields(loop, id), caster["coord"], func(_n): return 0)
		var targets: Array = receipt.get("affected_targets", [])
		var ids: Array = targets.map(func(target): return str(target["defender_id"]))
		var damages: Array = targets.map(func(target): return str(int(target["actual_damage"])))
		check(targets.size() == 3 and damages[0] != damages[1] and damages[1] != damages[2] and damages[0] != damages[2], "fixture: 風狼葬天擊 settles three receivers with distinct damage (%s)" % str(damages))
		scene.apply_loop(loop, "test")
		scene._process(0)
		check(cutin.clips.map(func(clip): return str(clip["strike"]["defender_id"])) == ids, "one clip per receiver, in the receipt's order")
		check(cutin.clips.map(func(clip): return [clip.get("defense_page", false), clip["first_shot"], clip["last_shot"]]) == [[false, true, false], [true, false, false], [true, false, true]], "the first clip opens, the later two are defense pages, the last one closes")
		var frame := [0]
		var impacts: Array = []
		cutin.impact.connect(func(strike, _attacker, _defender, _counter):
			var shown: Array = []
			for child in view.get_children():
				var digits: Node = child.get_node_or_null("DamageDigits")
				if digits != null: shown.append(str(digits.digits))
			impacts.append([frame[0], str(strike["defender_id"]), shown])
		)
		var pages: Array = [{}, {}, {}]
		var current: Dictionary = cutin.clips[0] if cutin.busy() else {}
		var page := 0
		while cutin.busy() and frame[0] < 3000:
			frame[0] += 1
			cutin._process(TICK)
			if not cutin.busy(): break
			if not is_same(cutin.clips[0], current):
				current = cutin.clips[0]
				page = mini(page + 1, 2)
			var seen: Dictionary = pages[page]
			if cutin.stage.size == Vector2(640, 480): seen["lead"] = true
			if cutin.scenery.visible and cutin.scenery.texture != null and cutin.scenery.texture.resource_path.ends_with("sp00_001.shp.png"): seen["attack_page"] = true
			if cutin.transition_shade.visible: seen["close"] = true
			if RuntimeReadback.result_text(cutin) != "": seen["result"] = RuntimeReadback.result_text(cutin)
		check(not cutin.busy(), "the three pages play out (%d frames)" % frame[0])
		check(impacts.map(func(entry): return entry[1]) == ids and impacts.map(func(entry): return entry[2]) == [damages.slice(0, 1), damages.slice(0, 2), damages], "each page's impact adds its own receiver's number to the map: one, then two, then three (%s)" % str(impacts))
		check(impacts.size() == 3 and impacts[0][0] < impacts[1][0] and impacts[1][0] < impacts[2][0], "the three map numbers come on three different frames")
		if hidden:
			check(cutin.cutin_hidden and not cutin.visible, "OPT-PACE 極快 keeps the close-up hidden")
		else:
			check(pages.map(func(seen): return [seen.get("lead", false), seen.get("attack_page", false), seen.get("close", false)]) == [[true, true, false], [false, false, false], [false, false, true]], "the cast lead and the SP00_001 attack page on the first page only, the darken and lighten on the last only (%s)" % str(pages))
			check(pages.map(func(seen): return seen.get("result", "")) == damages, "each page's result is its own receiver's damage (%s)" % str(pages))
		GameOptions.environment_preset = ""
		GameSettings._cache = {}
		scene.queue_free()
		await process_frame
