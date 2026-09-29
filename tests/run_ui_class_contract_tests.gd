extends "res://tests/support/TestSuite.gd"

## Whole-game UI class contracts from the 2026-09-23 playtest (lane P9): each check walks
## every instance of one class of problem instead of the one screen a playtest reported.
##   shape_scale  — no original-art TextureRect is drawn stretched: every selectable state of
##                  both system scrolls, the confirm pair, the memoir headings, dialogue
##                  faces, identity-strip portraits and equipment icons.
##   lit_registration — every lit menu shape (title ring, both system scrolls, 確定／取消) sits
##                  where its red glyphs cover the most of the panel's baked glyphs
##                  (manifest lit_glyph_registration), searched ±REGISTRATION_RADIUS px.
##   panel_alignment — every value printed beside a baked label (WINDOW10 strip, WINDOW21
##                  attribute column, WINDOW30 equipment slots, WINDOW40 gold) is centred
##                  on that label's glyph row and starts right of its colon; icons never
##                  cover a label glyph; the baked labels draw over the bars; the remake
##                  buttons stay clear of the gold box and of each other.
##   button_size    — a WINDOW50 button keeps the size its caller asked for at every height
##                  the game uses (24–43 px), so stacked menus (the town list) never touch.
##   word_breaks    — no wrapped line starts inside a protected name
##                  (content/generated/hsl/text/protected_words.json): every story／town
##                  corpus line that contains one, in the dialogue body and narration boxes
##                  under OPT-WORDBREAK 保護專名 (the original's 38-byte hard break, the default,
##                  cuts DIALOGUE_CUT_LINES of them — 雪｜拉, 通行｜證),
##                  every party of the town gold／party strip, and every equipment item's
##                  description in the status／equipment detail box; the shown text differs
##                  from the source only by inserted line breaks.
##   simplified_display — the SimplifiedDisplay autoload's seam shows every Control's traditional
##                  source text in the original font's forms (體力→体力, 開始新故事→开始新故事,
##                  後 kept as the original font draws it) while label.text stays the source.
##   glyph_coverage — every character the seam can show (simplified_chars.json) has a glyph in
##                  the project UI font chain (game/assets/ui_font.tres and its fallbacks); on
##                  macOS Godot resolves "PingFang SC" to PingFang HK, which lacks 杀敌远… and
##                  drew them as missing-glyph boxes until the explicit SC fallback was added.

const BattleSystemMenu = preload("res://game/battle/scene/BattleSystemMenu.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")


func _init() -> void:
	tag = "UI_CLASS_CONTRACT_TESTS"


const TITLE_MANIFEST := "res://content/imported/hsl/global/title/manifest.json"
## Search radius around the recorded offset; wider than any earlier drift (≤ 2 px).
const REGISTRATION_RADIUS := 4


func run() -> void:
	await shape_scale_contracts()
	lit_registration_contracts()
	await panel_alignment_contracts()
	await word_break_contracts()
	await button_size_contracts()
	await simplified_display_contracts()
	glyph_coverage_contracts()
	run_game_cursor()
	run_section_title()


func _glyph_mask(image: Image, panel: bool, rule: Dictionary) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	var dark := int(rule["panel_glyph_max_channel"])
	var margin := int(rule["lit_glyph_red_margin"])
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a8 == 0:
				continue
			var hit := maxi(c.r8, maxi(c.g8, c.b8)) < dark if panel else (c.r8 > c.g8 + margin and c.r8 > c.b8 + margin)
			mask[y * image.get_width() + x] = 1 if hit else 0
	return mask


func _overlap(panel: PackedByteArray, panel_width: int, panel_height: int, lit_points: PackedVector2Array, offset: Vector2i) -> int:
	var count := 0
	for point in lit_points:
		var x := int(point.x) + offset.x
		var y := int(point.y) + offset.y
		if x >= 0 and y >= 0 and x < panel_width and y < panel_height and panel[y * panel_width + x] == 1:
			count += 1
	return count


func lit_registration_contracts() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TITLE_MANIFEST))
	var rule: Dictionary = manifest["lit_glyph_registration"]
	var shapes: Dictionary = manifest["shapes"]
	var checked := 0
	for group in [["items", "ring", "lit_offset_in_ring"], ["system_items", "system_panel", "lit_offset_in_panel"], ["world_items", "world_panel", "lit_offset_in_panel"], ["confirm_items", "confirm_buttons", "lit_offset_in_buttons"]]:
		var panel_image: Image = load(str(shapes[group[1]]["texture"])).get_image()
		var panel := _glyph_mask(panel_image, true, rule)
		for item in manifest[group[0]]:
			var lit_image: Image = load(str(shapes[item["lit"]]["texture"])).get_image()
			var lit := _glyph_mask(lit_image, false, rule)
			var points := PackedVector2Array()
			for index in lit.size():
				if lit[index] == 1:
					points.append(Vector2(index % lit_image.get_width(), index / lit_image.get_width()))
			var recorded := Vector2i(int(item[group[2]][0]), int(item[group[2]][1]))
			var at_recorded := _overlap(panel, panel_image.get_width(), panel_image.get_height(), points, recorded)
			var best := recorded
			var best_count := at_recorded
			for dy in range(-REGISTRATION_RADIUS, REGISTRATION_RADIUS + 1):
				for dx in range(-REGISTRATION_RADIUS, REGISTRATION_RADIUS + 1):
					var count := _overlap(panel, panel_image.get_width(), panel_image.get_height(), points, recorded + Vector2i(dx, dy))
					if count > best_count:
						best_count = count
						best = recorded + Vector2i(dx, dy)
			check(points.size() > 50 and best == recorded, "%s %s lit at %s, glyph registration puts it at %s (%d vs %d glyph px)" % [group[0], item["id"], recorded, best, at_recorded, best_count])
			checked += 1
	check(checked == 17, "lit registration walks every lit menu shape (3 title, 6+6 scroll, 2 confirm), got %d" % checked)


## Every visible TextureRect under `node` that scales its texture over the rect
## (STRETCH_SCALE with the texture-sized minimum) must be exactly the texture's size.
func assert_unstretched(node: Node, context: String) -> void:
	for child in node.find_children("*", "TextureRect", true, false):
		var rect := child as TextureRect
		if rect.texture == null or not rect.is_visible_in_tree():
			continue
		if rect.stretch_mode != TextureRect.STRETCH_SCALE or rect.expand_mode != TextureRect.EXPAND_KEEP_SIZE:
			continue
		check(rect.size == rect.texture.get_size(), "%s: %s draws %s stretched to %s" % [context, rect.get_path(), rect.texture.get_size(), rect.size])


func shape_scale_contracts() -> void:
	for variant in ["battle", "world"]:
		var menu = BattleSystemMenu.new()
		menu.variant = variant
		root.add_child(menu)
		await process_frame
		menu.open()
		# Largest item first, then every other: the reused Lit rect must shrink back.
		var order: Array = range(menu.items.size())
		order.sort_custom(func(a, b): return menu.manifest["shapes"][menu.items[a]["lit"]]["size"][0] > menu.manifest["shapes"][menu.items[b]["lit"]]["size"][0])
		for index in order:
			menu.select(index)
			var size: Array = menu.manifest["shapes"][menu.items[index]["lit"]]["size"]
			check(menu._lit.size == Vector2(size[0], size[1]), "%s scroll item %s lit drawn at %s, shape is %s" % [variant, menu.items[index]["id"], menu._lit.size, size])
			assert_unstretched(menu, "%s scroll item %d" % [variant, index])
		for index in [0, 1, 0]:
			menu._show_confirm_lit(index)
			menu._confirm_box.visible = true
			assert_unstretched(menu._confirm_box, "%s confirm %d" % [variant, index])
		for mode in ["save", "load", "save"]:
			menu._show_memoir_list(mode)
			assert_unstretched(menu._memoir_box, "%s memoir %s" % [variant, mode])
		menu.queue_free()
		await process_frame
	# Equipment icons: a large icon then a small one in the same slot.
	var view = preload("res://game/battle/scene/BattleEquipmentView.gd").new()
	root.add_child(view)
	await process_frame
	var sizes := {}
	for code in preload("res://game/sim/EquipmentCatalog.gd").items():
		var details: Dictionary = preload("res://game/sim/EquipmentCatalog.gd").items()[code]
		var shape := BattleUISkin.texture(str(details["icon"]))
		if shape != null and details.get("slot", "") == "weapon":
			sizes[int(shape.get_size().x * 1000 + shape.get_size().y)] = int(code)
	var codes: Array = sizes.keys()
	codes.sort()
	codes.reverse()
	for key in codes:
		view.show_unit({"equipment": [{"slot": "weapon", "item_code": sizes[key]}]})
		assert_unstretched(view, "equipment icon %d" % sizes[key])
	view.queue_free()
	await process_frame


## Rows (and their right edge) of baked label glyphs — the golden caption colour of the
## original boards — inside `band` of `image`: [[top, bottom, right], ...] top to bottom.
## A glyph row may have blank scanlines inside it (the 頭／武 radicals): gaps shorter than
## LABEL_ROW_GAP stay in the row.
const LABEL_ROW_GAP := 4
## WINDOW21's stone texture has caption-coloured specks between rows (single pixels at
## rows 120／122／198-203): its scanlines need this many hits to count as glyph.
const WINDOW21_MIN_HITS := 3
## The baked labels themselves drift ±2 px from a regular row pitch, and the original draws
## WINDOW10's FONT.24 values 3 px above the caption row centre (姓名 ink y 27–42 against the
## caption row centred at 37, menus_ui §7), so a value counts as centred within this tolerance.
const LABEL_CENTRE_TOLERANCE := 3.0


func _label_rows(image: Image, band: Rect2i, min_hits: int = 1) -> Array:
	var rows: Array = []
	var start := -1
	var last := -1
	var right := -1
	for y in range(band.position.y, band.end.y + LABEL_ROW_GAP):
		var row_right := -1
		var hits := 0
		if y < band.end.y:
			for x in range(band.position.x, band.end.x):
				var c := image.get_pixel(x, y)
				if c.a8 > 0 and c.r8 > 200 and c.r8 > c.b8 + 100 and c.g8 > 90 and c.g8 < 200:
					row_right = x
					hits += 1
		if hits < min_hits:
			row_right = -1
		if row_right >= 0:
			if start < 0:
				start = y
			last = y
			right = maxi(right, row_right)
		elif start >= 0 and y - last >= LABEL_ROW_GAP:
			if last - start >= 6:
				rows.append([start, last, right])
			start = -1
			right = -1
	return rows


func _check_beside(label: Label, board_at: Vector2, row: Array, context: String) -> void:
	var rect := Rect2(label.global_position, label.size)
	var centre := board_at.y + (float(row[0]) + float(row[1])) / 2.0
	check(absf(rect.get_center().y - centre) <= LABEL_CENTRE_TOLERANCE, "%s: value centred at y %.1f, its baked label row centres at %.1f" % [context, rect.get_center().y, centre])
	check(rect.position.x > board_at.x + float(row[2]), "%s: value starts at x %.1f, left of the label colon end %.1f" % [context, rect.position.x, board_at.x + float(row[2])])


func _board(parent: Node, file: String) -> TextureRect:
	for child in parent.get_children():
		if child is TextureRect and child.texture != null and child.texture.resource_path.ends_with(file):
			return child
	return null


func panel_alignment_contracts() -> void:
	var loop := preload("res://tests/support/BattleFixture.gd").loop()
	var unit: Dictionary = preload("res://game/sim/loop/BattlePlayLoop.gd").unit_ref(loop, "leonard").duplicate(true)
	var panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.show_unit(unit, true)
	panel.gold_label.text = "230"
	var vitals = panel.vitals
	# WINDOW10 strip: the left labels (等級／經驗 share a row) and the right board labels.
	var board: TextureRect = _board(vitals, "WINDOW10.SHP.png")
	check(board.get_index() > vitals.hp_bar.get_index() and board.get_index() > vitals.mp_bar.get_index() and board.get_index() > vitals.st_bar.get_index(), "baked labels draw over the bars' left ends (frame_006)")
	var w10 := board.texture.get_image()
	var at: Vector2 = board.global_position
	var left := _label_rows(w10, Rect2i(0, 0, 80, 144))
	check(left.size() == 4, "WINDOW10 has four left label rows, found %d" % left.size())
	var level_row: Array = _label_rows(w10, Rect2i(0, 0, 60, 40))[0]
	var exp_row: Array = _label_rows(w10, Rect2i(80, 0, 80, 40))[0]
	_check_beside(vitals.values["level"], at, level_row, "strip 等級")
	_check_beside(vitals.values["exp"], at, exp_row, "strip 經驗")
	_check_beside(vitals.values["hp"], at, left[1], "strip 生命力")
	_check_beside(vitals.values["mp"], at, left[2], "strip 魔法力")
	var right := _label_rows(w10, Rect2i(258, 0, 82, 144))
	check(right.size() == 4, "WINDOW10 has four right label rows, found %d" % right.size())
	for index in range(4):
		_check_beside(vitals.values[["name", "role", "race", "state"][index]], at, right[index], "strip " + ["姓名", "稱號", "種族", "狀態"][index])
	# WINDOW21 attribute column.
	var w21_rect: TextureRect = _board(panel, "WINDOW21.png")
	check(w21_rect != null, "the status page draws WINDOW21 (the frame with the nine baked attribute labels)")
	if w21_rect != null:
		var rows := _label_rows(w21_rect.texture.get_image(), Rect2i(0, 0, 112, 264), WINDOW21_MIN_HITS)
		check(rows.size() == 9, "WINDOW21 has nine label rows, found %d" % rows.size())
		for index in range(mini(rows.size(), panel.STAT_KEYS.size())):
			_check_beside(panel.stat_values[panel.STAT_KEYS[index]], w21_rect.global_position, rows[index], "attribute " + panel.STAT_KEYS[index])
	# WINDOW30 equipment slots: names beside their labels, icons off the label glyphs.
	var view = panel.equipment_view
	var w30: TextureRect = _board(view, "WINDOW30.SHP.png")
	var slot_rows := _label_rows(w30.texture.get_image(), Rect2i(0, 0, 60, 168))
	var slot_rows_right := _label_rows(w30.texture.get_image(), Rect2i(180, 0, 60, 168))
	check(slot_rows.size() == 3 and slot_rows_right.size() == 3, "WINDOW30 has three label rows per column, found %d／%d" % [slot_rows.size(), slot_rows_right.size()])
	for index in range(view.SLOTS.size()):
		var slot: String = view.SLOTS[index]
		var rows_for := slot_rows if index % 2 == 0 else slot_rows_right
		if rows_for.size() == 3:
			_check_beside(view.labels[slot], w30.global_position, rows_for[floori(index / 2.0)], "equipment " + slot)
		var icon: TextureRect = view.icons[slot]
		if icon.texture != null:
			var icon_rect := Rect2(icon.global_position, icon.size)
			var label_right := w30.global_position.x + float(rows_for[floori(index / 2.0)][2])
			check(icon_rect.position.x > label_right, "equipment %s icon at x %.0f covers its label (colon ends %.0f)" % [slot, icon_rect.position.x, label_right])
	# WINDOW40 gold box and the remake button strip.
	var gold_box: TextureRect = _board(panel, "WINDOW40.SHP.png")
	check(gold_box != null, "the status page draws the WINDOW40 $: box")
	if gold_box != null:
		var box := Rect2(gold_box.global_position, gold_box.size)
		var dollar := _label_rows(gold_box.texture.get_image(), Rect2i(0, 0, 60, 32))
		check(dollar.size() == 1, "WINDOW40 has one baked $: row")
		if dollar.size() == 1:
			_check_beside(panel.gold_label, gold_box.global_position, dollar[0], "money")
		check(box.encloses(Rect2(panel.gold_label.global_position, panel.gold_label.size)), "the amount stays inside the $: box")
		var buttons: Array = panel.get_children().filter(func(child): return child is Button)
		for index in range(buttons.size()):
			var rect := Rect2(buttons[index].global_position, buttons[index].size)
			check(not rect.intersects(box), "button %s stays clear of the $: box" % buttons[index].text)
			check(rect.end.x <= 640, "button %s stays on screen" % buttons[index].text)
			for other in range(index + 1, buttons.size()):
				check(not rect.intersects(Rect2(buttons[other].global_position, buttons[other].size)), "buttons %s and %s do not overlap" % [buttons[index].text, buttons[other].text])
	panel.queue_free()
	await process_frame


func _check_no_split(label: Label, source: String, context: String) -> void:
	var shown := label.text
	check(shown.replace("\n", "") == source.replace("\n", ""), "%s: shown text is the source plus line breaks" % context)
	check(label.get_line_count() == BattleUISkin.line_starts(label, shown).size(), "%s: the measured wrap has the label's own line count (%d vs %d)" % [context, BattleUISkin.line_starts(label, shown).size(), label.get_line_count()])
	# Where each shown character came from in the source: an inserted line break (the dialogue
	# rows are all inserted breaks) does not hide a name cut across it.
	var source_at := PackedInt32Array()
	var next := 0
	for index in shown.length():
		source_at.append(next)
		if next < source.length() and shown[index] == source[next]:
			next += 1
	for start in BattleUISkin.line_starts(label, shown):
		var in_source: int = source_at[start] if start < shown.length() else source.length()
		if BattleUISkin.split_word_start(shown, start) >= 0 or BattleUISkin.split_word_start(source, in_source) >= 0:
			check(false, "%s: a line starts inside a protected name at %d: …%s…" % [context, start, shown.substr(maxi(0, start - 4), 8)])
			return
	checked_wraps += 1


var checked_wraps := 0
## Corpus lines whose original 38-byte rows cut a protected name (dialogue-line-breaks).
const DIALOGUE_CUT_LINES := 17


func word_break_contracts() -> void:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(preload("res://game/sim/ContentPaths.gd").PROTECTED_WORDS))
	var words := BattleUISkin.protected_words()
	check(words.size() == table["words"].size() and words.size() > 300, "protected word table loads (%d words)" % words.size())
	var lines: Array[String] = []
	var scripts := DirAccess.get_files_at("res://content/imported/hsl/story_corpus/scripts")
	for file in scripts:
		if not file.begins_with("STORY") or not file.ends_with(".json"):
			continue
		for message in JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/story_corpus/scripts/" + file))["messages"]:
			if str(message.get("text", "")) != "":
				lines.append(str(message["text"]))
	for text in JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/global/world_map/town_messages.json"))["messages"].values():
		if str(text) != "":
			lines.append(str(text))
	check(lines.size() == int(table["corpus"]["lines"]), "the wrap check reads the same corpus the table scanned (%d lines)" % lines.size())
	var at_risk: Array[String] = lines.filter(func(line): return Array(words).any(func(word): return line.contains(word)))
	check(at_risk.size() == int(table["corpus"]["lines_with_protected_words"]), "every corpus line with a protected name is walked (%d)" % at_risk.size())
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	root.add_child(dialogue)
	await process_frame
	dialogue.configure_portraits(preload("res://game/sim/ContentPaths.gd").ACTOR_PORTRAITS)
	var cut_lines := 0
	for line in at_risk:
		var rows: PackedStringArray = BattleUISkin.message_rows(line)
		var at := 0
		for row_index in range(rows.size() - 1):
			at += rows[row_index].length()
			if line[at] == "\n":
				at += 1
			elif BattleUISkin.split_word_start(line, at) >= 0:
				cut_lines += 1
				break
	check(cut_lines == DIALOGUE_CUT_LINES, "OPT-WORDBREAK 原版: the 38-byte hard break cuts a name in %d corpus lines" % cut_lines)
	GameOptions.environment_preset = GameOptions.PRESET_COMFORT
	checked_wraps = 0
	for index in range(at_risk.size()):
		dialogue.show_message("wrap%d" % index, "雷歐納德", at_risk[index], "001")
		_check_no_split(dialogue.body_label, at_risk[index], "dialogue line %d" % index)
		dialogue.show_narration("narr%d" % index, at_risk[index])
		_check_no_split(dialogue.body_label, at_risk[index], "narration line %d" % index)
	check(checked_wraps == 2 * at_risk.size(), "every at-risk line wraps without a split name in both boxes (%d of %d)" % [checked_wraps, 2 * at_risk.size()])
	GameOptions.environment_preset = ""
	dialogue.queue_free()
	# Equipment detail box (BattleEquipmentView, shared by the status page, item／give views and
	# 整理裝備): 0x436d70 has 0x412060 draw the 0x430710 text unwrapped, one FONT.15 row per "#"
	# at (x+8, y+12+16i) — 153 鐵護輪 is its name with the 0x430520 job bracket and 56 防禦力.
	var view = preload("res://game/battle/scene/BattleEquipmentView.gd").new()
	root.add_child(view)
	await process_frame
	var catalog: Dictionary = preload("res://game/sim/EquipmentCatalog.gd").items()
	view.show_description(catalog["153"])
	var drawn: Array = view.detail_rows.get_children().filter(func(child): return child is Label)
	check(drawn.map(func(row): return row.text) == ["鐵護輪(劍,弓,翼,獸)", "防禦力6"] and drawn[1].position.y - drawn[0].position.y == 16.0, "the detail box draws 鐵護輪 as two unwrapped rows (%s)" % [drawn.map(func(row): return row.text)])
	view.queue_free()
	await process_frame


## Every button height passed to UISkin.button in game/ (grep of the call sites).
const BUTTON_HEIGHTS := [24, 28, 30, 32, 34, 36, 43]


func button_size_contracts() -> void:
	var holder := Control.new()
	root.add_child(holder)
	for height in BUTTON_HEIGHTS:
		var button := BattleUISkin.button(holder, "離開城鎮", Vector2.ZERO, Vector2(232, height))
		await process_frame
		check(button.size == Vector2(232, height), "a %d px button keeps its size, got %s" % [height, button.size])
	# The town's root entries are text rows on the WINDOW70 board since R5-L5b (original frames
	# 03／04).
	var Town = preload("res://game/world/TownRuntime.gd")
	check(Town.MENU_ROW_PITCH >= Town.MENU_ROW_SIZE.y, "town board rows do not overlap (pitch %.0f, row %.0f)" % [Town.MENU_ROW_PITCH, Town.MENU_ROW_SIZE.y])
	holder.queue_free()
	await process_frame


func glyph_coverage_contracts() -> void:
	var font: Font = load(str(ProjectSettings.get_setting("gui/theme/custom_font")))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/text/simplified_chars.json"))
	var missing := PackedStringArray()
	for shown in (parsed["chars"] as Dictionary).values():
		var character := String(shown)
		if not font.has_char(character.unicode_at(0)):
			missing.append(character)
	check(missing.is_empty(), "UI font chain draws every simplified display character (missing: %s)" % "".join(missing))


func simplified_display_contracts() -> void:
	check(TranslationServer.translate("開始新故事") == "开始新故事", "simplified display seam is installed by the autoload")
	check(TranslationServer.translate("戰亂開始後") == "战乱开始後", "the original font keeps 後／於 traditional")
	check(TranslationServer.translate("職業") == "职业", "職 shows 职 (the original font's 翻 glyph is a slot bug)")
	var label := Label.new()
	label.text = "體力"
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.text = "[color=red]緹娜[/color]說"
	root.add_child(label)
	root.add_child(rich)
	await process_frame
	check(label.text == "體力", "label.text keeps the traditional source")
	check(label.atr(label.text) == "体力", "a Label displays the converted text")
	check(rich.get_parsed_text() == "缇娜说", "a RichTextLabel parses the converted text")
	label.queue_free()
	rich.queue_free()
	await process_frame


# ---- run_ui_class_contract_tests.gd ----
## The original game cursor (game_cursor/README.md): every original OBS defines object 2 游標 the
## same way — CURSOR01..CURSOR10, obj_Shape_Delay 5, defProcCursor, planeCursor (resource-derived,
## `hsl check game_cursor`). 0x430410 puts the object on the mouse and 0x45e5a6 shows the next
## shape every delay + 1 = 6 ticks, looping after ten (static-derived); the recording's CURSOR10
## returns every 1.151 s = 60 ticks of 19.2 ms (runtime-measured). A shape draws at the position
## minus its SHP draw origin, so the origin is the hotspot — the red orb on every frame; the
## game draws it into its own 640×480 picture on planeCursor, the top plane.
## Checks the GameCursor autoload against that, and that no other game code sets a cursor.

const MANIFEST_PATH := "res://content/imported/hsl/shared/game_cursor/manifest.json"
const AUTOLOAD_PATH := "res://game/cursor/GameCursor.gd"


func run_game_cursor() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_test_manifest(manifest)
	var cursor: Node = root.get_node_or_null("GameCursor")
	check(cursor != null, "the GameCursor autoload is installed for every scene")
	if cursor == null:
		return
	_test_frames_and_hotspots(cursor, manifest)
	_test_animation(cursor)
	_test_no_other_cursor_source()


func _test_manifest(manifest: Dictionary) -> void:
	var fields: Dictionary = manifest.get("source_fields", {})
	_assert_eq(str(fields.get("obj_Process_Code", "")), "defProcCursor", "the cursor object runs defProcCursor")
	_assert_eq(str(fields.get("obj_Plane", "")), "planeCursor", "it draws on planeCursor, above every menu plane")
	_assert_eq(int(fields.get("obj_Shape_Number", 0)), 10, "ten shapes CURSOR01..CURSOR10")
	_assert_eq(int(manifest.get("frame_ticks", 0)), int(fields.get("obj_Shape_Delay", 0)) + 1, "a shape shows obj_Shape_Delay + 1 ticks (0x45e5a6)")
	_assert_eq(int(manifest.get("frame_ticks", 0)), 6, "six ticks a shape, a 60-tick loop")
	check(int(manifest.get("obs_definitions", 0)) >= 100 and (manifest.get("obs_disagreements", [0]) as Array).is_empty(), "every OBS that defines the cursor defines the same one (%d)" % int(manifest.get("obs_definitions", 0)))


func _test_frames_and_hotspots(cursor: Node, manifest: Dictionary) -> void:
	var frames: Array = manifest.get("frames", [])
	_assert_eq(cursor.frames.size(), frames.size(), "the autoload loads every shape")
	var on_orb := 0
	for index in range(mini(frames.size(), cursor.frames.size())):
		var origin := Vector2i(int(frames[index]["draw_origin"][0]), int(frames[index]["draw_origin"][1]))
		_assert_eq(cursor.hotspots[index], origin, "shape %d's hotspot is its SHP draw origin" % (index + 1))
		var image: Image = cursor.frames[index].get_image()
		_assert_eq(Vector2i(image.get_width(), image.get_height()), Vector2i(int(frames[index]["size"][0]), int(frames[index]["size"][1])), "shape %d keeps its source size" % (index + 1))
		var pixel := image.get_pixelv(origin)
		if pixel.a > 0.9 and pixel.r > 0.7 and pixel.g < 0.2 and pixel.b < 0.2:
			on_orb += 1
	_assert_eq(on_orb, frames.size(), "the hotspot is the red orb on every shape")
	_assert_eq(cursor.hotspots[0], Vector2i(8, 3), "the wide first shape points with (8,3)")


func _test_animation(cursor: Node) -> void:
	cursor.frame_index = 0
	cursor._ticks_in_frame = 0
	cursor.apply_frame()
	var changes: Array[int] = []
	for tick in range(1, 61):
		var before: int = cursor.frame_index
		cursor.advance_tick()
		if cursor.frame_index != before:
			changes.append(tick)
	_assert_eq(changes, [6, 12, 18, 24, 30, 36, 42, 48, 54, 60], "the next shape every six ticks")
	_assert_eq(cursor.frame_index, 0, "after the tenth shape the loop starts again (60 ticks)")
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	cursor.advance_tick()
	var sprite: Sprite2D = cursor.sprite
	_assert_eq(sprite.texture, cursor.frames[1], "each new shape is drawn")
	check(sprite.get_viewport() == root and cursor.layer.layer > 1024 and sprite.global_scale == Vector2.ONE, "the cursor draws at source size in the 640×480 picture above every layer and popup (%d), so the window scales it with the game" % cursor.layer.layer)
	cursor.show_at(Vector2(100.7, 50.2))
	_assert_eq(Vector2i(sprite.position + sprite.offset) + cursor.hotspots[1], Vector2i(100, 50), "the hotspot lands on the logical pixel under the pointer")
	sprite.hide()
	cursor.frame_index = 0
	cursor._ticks_in_frame = 0
	cursor.apply_frame()


## One cursor for every screen: only GameCursor sets the mouse cursor image or shape or hides
## the system pointer.
func _test_no_other_cursor_source() -> void:
	var offenders: Array[String] = []
	var pattern := RegEx.create_from_string("set_custom_mouse_cursor|mouse_default_cursor_shape|cursor_set_shape|cursor_set_custom_image|Input\\.set_default_cursor_shape|mouse_mode")
	for path in _files("res://game", [".gd", ".tscn"]):
		if path == AUTOLOAD_PATH:
			continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			offenders.append(path)
	_assert_eq(offenders, [], "no other game file sets a mouse cursor")


func _files(directory: String, suffixes: Array) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for name in dir.get_files():
		for suffix in suffixes:
			if name.ends_with(suffix):
				found.append(directory.path_join(name))
	for name in dir.get_directories():
		found.append_array(_files(directory.path_join(name), suffixes))
	return found


# ---- run_ui_class_contract_tests.gd ----
## actShowSectionName title card (OpeningCinematics; original_tick_counts.md §2): the
## 0x452f32 sub-state machine tick by tick, the two drawn layers (subtractive LEVELSEC band
## stretched vertically, WORD name cross-faded) and that every registered scene's title card
## has its art and plays through this one path.

const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const BattleOpeningCoordinator = preload("res://game/battle/runtime/BattleOpeningCoordinator.gd")
const CAMPAIGN := "res://content/battles/campaign.json"
const ZOOM_ONE := 0x10000


func run_section_title() -> void:
	_sub_state_ticks()
	_skip_ticks()
	_view_layers()
	_every_title_card()


func _state(tick: int, skip_hold_tick: int = 0) -> Dictionary:
	return RulesReadback.section_title_state_at(tick, skip_hold_tick)


func _expect(tick: int, sub: int, band: int, name_level: int, zoom: int, label: String, skip_hold_tick: int = 0) -> void:
	var state := _state(tick, skip_hold_tick)
	var got := [int(state["sub"]), int(state["band_level"]), int(state["name_level"]), int(state["zoom"])]
	_assert_eq(got, [sub, band, name_level, zoom], "tick %d: %s [sub, band, name, zoom]" % [tick, label])


## Unskipped: 1 + 51 + 56 + 51 + 320 + 51 + 51 + 1 = 582 ticks. The level ramps reload their
## 3-tick counter and test the level before stepping it (16 steps, then one more reload).
func _sub_state_ticks() -> void:
	_expect(1, 1, 0, 0, 0x80000, "sub-state 0 sets zoom 8.0 and both levels 0")
	_expect(3, 1, 0, 0, 0x80000, "the first band step waits for the counter's third tick")
	_expect(4, 1, 1, 0, 0x80000, "band level 1 on the first reload")
	_expect(49, 1, 16, 0, 0x80000, "band level 16 after 16 reloads, still zoomed 8.0")
	_expect(51, 1, 16, 0, 0x80000, "band ramp still waits for its 17th reload")
	_expect(52, 2, 16, 0, 0x80000, "17th reload finds level 16: sub-state 2 (51-tick ramp)")
	_expect(53, 2, 16, 0, 0x80000 - 0x2000, "zoom steps down 0.125 per tick")
	_expect(105, 2, 16, 0, 0x16000, "zoom mid-shrink 1.375")
	_expect(107, 2, 16, 0, 0x12000, "zoom 1.125 one tick before the band settles")
	_expect(108, 3, 16, 0, ZOOM_ONE, "zoom clamps at 1.0 on the 56th tick: sub-state 3")
	_expect(111, 3, 16, 1, ZOOM_ONE, "name level 1 on the name ramp's first reload")
	_expect(156, 3, 16, 16, ZOOM_ONE, "name level 16")
	_expect(159, 4, 16, 16, ZOOM_ONE, "name ramp ends on tick 159: the hold begins (159 ticks in)")
	_assert_eq(BattleOpeningCoordinator.SECTION_TITLE_IN_TICKS, 159, "the coordinator's entry length is the state machine's")
	_expect(300, 4, 16, 16, ZOOM_ONE, "hold keeps both layers fully shown")
	_assert_eq(int(_state(300)["hold"]), 320 - (300 - 159), "the hold counter drops one per tick")
	_expect(478, 4, 16, 16, ZOOM_ONE, "hold tick 319")
	_expect(479, 5, 16, 16, ZOOM_ONE, "the 320th hold tick ends the hold")
	_expect(482, 5, 16, 15, ZOOM_ONE, "name level steps down on the exit ramp's first reload")
	_expect(504, 5, 16, 8, ZOOM_ONE, "exit mid-point of the name ramp: name level 8")
	_expect(527, 5, 16, 0, ZOOM_ONE, "name level 0")
	_expect(530, 6, 16, 0, ZOOM_ONE, "name ramp ends on its 17th reload: sub-state 6")
	_expect(531, 6, 16, 0, ZOOM_ONE + 0x2000, "the band grows 0.125 per tick")
	_expect(555, 6, 8, 0, ZOOM_ONE + 25 * 0x2000, "exit mid-point of the band ramp: level 8, zoom 4.125")
	_expect(578, 6, 0, 0, ZOOM_ONE + 48 * 0x2000, "band level 0")
	_expect(581, 7, 0, 0, 0x76000, "band ramp ends at zoom 7.375, not 8.0")
	_expect(582, OpeningCinematics.TITLE_SUB_DONE, 0, 0, 0x76000, "sub-state 7 hands the VM on")
	_assert_eq(int(_state(582)["tick"]), 582, "the card lasts 582 ticks unskipped")
	_assert_eq(int(_state(9999)["tick"]), 582, "the machine stops after sub-state 7")
	_assert_eq(BattleOpeningCoordinator.SECTION_TITLE_IN_TICKS + BattleOpeningCoordinator.SECTION_TITLE_HOLD_TICKS + BattleOpeningCoordinator.SECTION_TITLE_OUT_TICKS, 582, "the coordinator waits the same 582 ticks")
	_assert_eq(BattleOpeningCoordinator.SECTION_TITLE_OUT_TICKS, 582 - 479, "the coordinator's exit length is the state machine's")


## Only sub-state 4 reads the key／click; the tick that sees it ends the hold.
func _skip_ticks() -> void:
	var early := OpeningCinematics.section_title_new_state()
	for tick in 159:
		OpeningCinematics.section_title_step(early, true)
	_assert_eq([int(early["sub"]), int(early["tick"])], [4, 159], "input on every entry tick does not shorten the entry")
	_expect(160, 5, 16, 16, ZOOM_ONE, "a key on the first hold tick ends the hold at once", 1)
	_assert_eq(int(_state(9999, 1)["tick"]), 263, "first-hold-tick skip: 159 + 1 + 103 = 263 ticks")
	_assert_eq(int(_state(9999, 100)["tick"]), 159 + 100 + 103, "a key on hold tick 100 leaves the 103-tick exit")
	_expect(160 + 25, 5, 16, 8, ZOOM_ONE, "skipped exit: name level 8 on the 25th exit tick", 1)
	var late := _state(479)
	OpeningCinematics.section_title_step(late, true)
	_assert_eq([int(late["sub"]), int(late["name_level"])], [5, 16], "input after the hold is ignored by the exit ramp")


func _view_layers() -> void:
	var name_texture: Texture2D = load("res://content/imported/hsl/chapter01/battle051/section_title.png")
	var band_record: Dictionary = BattleUISkin.data()["assets"][OpeningCinematics.TITLE_BAND_ASSET]
	_assert_eq(band_record["source_member"], "SHAPE\\LEVELSEC.SHP", "the band is the shape 0x451818 loads")
	_assert_eq(band_record["draw_origin"], [320.0, 104.0], "LEVELSEC origin is its centre")
	var band_origin := Vector2(float(band_record["draw_origin"][0]), float(band_record["draw_origin"][1]))
	var view := OpeningCinematics.build_section_title_view(name_texture, BattleUISkin.texture(OpeningCinematics.TITLE_BAND_ASSET), band_origin)
	var band: TextureRect = view.get_node("SectionTitleBand")
	var title_name: TextureRect = view.get_node("SectionTitleName")
	_assert_eq(band.texture.get_size(), Vector2(640, 208), "band art 640×208")
	_assert_true(band.material is CanvasItemMaterial and (band.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_SUB, "the band is subtracted from the scene (pixel kind 10／11)")
	_assert_eq(band.position, Vector2(0, 136), "band origin on the view's (320,240)")
	_assert_eq(band.pivot_offset, Vector2(320, 104), "the band stretches about its origin")
	_assert_eq(title_name.position, Vector2(320 - 80, 240 - 39), "WORD051 (161×78, origin 80,39) centred on (320,240)")
	_assert_eq(title_name.scale, Vector2.ONE, "the name is drawn at 1×")
	_assert_true(title_name.material == null, "the name is cross-faded, not subtracted")
	var expectations := [
		[1, false, 0.0, 8.0, false, 0.0],
		[4, true, 1.0 / 16.0, 8.0, false, 0.0],
		[49, true, 1.0, 8.0, false, 0.0],
		[105, true, 1.0, 1.375, false, 0.0],
		[108, true, 1.0, 1.0, false, 0.0],
		[156, true, 1.0, 1.0, true, 1.0],
		[300, true, 1.0, 1.0, true, 1.0],
		[504, true, 1.0, 1.0, true, 0.5],
		[555, true, 0.5, 4.125, false, 0.0],
		[582, false, 0.0, 7.375, false, 0.0],
	]
	for row in expectations:
		OpeningCinematics.apply_section_title_state(view, _state(int(row[0])))
		var got := [band.visible, band.modulate.a, band.scale, title_name.visible, title_name.modulate.a]
		var want := [row[1], row[2], Vector2(1.0, row[3]), row[4], row[5]]
		_assert_true(got[0] == want[0] and is_equal_approx(got[1], want[1]) and got[2].is_equal_approx(want[2]) and got[3] == want[3] and is_equal_approx(got[4], want[4]),
			"tick %d: band visible／alpha／scale, name visible／alpha %s want %s" % [int(row[0]), str(got), str(want)])
	_assert_true(is_equal_approx(view.modulate.a, 1.0), "the card is not faded as a whole; each layer carries its own level")
	view.free()


## Every registered scene whose opening or winfail chain has actShowSectionName names a
## WORD art that loads; the token's kind is handled only by BattleOpeningCoordinator, which
## hands the drawing to OpeningCinematics.
func _every_title_card() -> void:
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CAMPAIGN))
	var titled := 0
	for level in campaign["battles"]:
		var path := str(campaign["battles"][level]["scenario"])
		if not path.ends_with(".json"):
			continue
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var resources: Dictionary = scenario.get("resources", {})
		var events: Array = []
		var timeline_path := str(resources.get("opening_timeline", ""))
		if timeline_path != "":
			events.append_array((JSON.parse_string(FileAccess.get_file_as_string(timeline_path)) as Dictionary).get("events", []))
		var chains: Dictionary = (scenario.get("scenario_rules", {}) as Dictionary).get("status_timelines", {})
		for key in chains:
			var chain: Variant = chains[key]
			events.append_array(chain if chain is Array else (chain as Dictionary).get("events", []))
		var has_title := events.any(func(event): return event is Dictionary and str(event.get("kind", "")) == "section_title_resource")
		if not has_title:
			continue
		titled += 1
		var evidence_path := str(resources.get("message_text_evidence", ""))
		var title: Variant = (JSON.parse_string(FileAccess.get_file_as_string(evidence_path)) as Dictionary).get("section_title") if evidence_path != "" else null
		var res_path := str((title as Dictionary).get("res_path", "")) if title is Dictionary else ""
		check(res_path != "" and ResourceLoader.exists(res_path) and load(res_path) is Texture2D, "level %s: its title card art loads (%s)" % [level, res_path])
	check(titled >= 40, "the campaign's title cards were found (%d scenes)" % titled)
	var handlers: Array[String] = []
	_scan_for_kind("res://game", handlers)
	_assert_eq(handlers, ["res://game/battle/runtime/BattleOpeningCoordinator.gd"], "only the opening coordinator handles section_title_resource")


func _scan_for_kind(dir_path: String, found: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	for sub in dir.get_directories():
		_scan_for_kind(dir_path.path_join(sub), found)
	for file in dir.get_files():
		if file.ends_with(".gd") and FileAccess.get_file_as_string(dir_path.path_join(file)).contains("\"section_title_resource\""):
			found.append(dir_path.path_join(file))
