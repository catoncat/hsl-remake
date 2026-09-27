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
##                  corpus line that contains one, in the dialogue body and narration boxes,
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
## The baked labels themselves drift ±2 px from a regular row pitch, so a value counts as
## centred on its label within this tolerance.
const LABEL_CENTRE_TOLERANCE := 2.5


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
	var unit: Dictionary = preload("res://game/sim/loop/BattlePlayLoop.gd")._unit(loop, "leonard").duplicate(true)
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
	checked_wraps = 0
	for index in range(at_risk.size()):
		dialogue.show_message("wrap%d" % index, "雷歐納德", at_risk[index], "001")
		_check_no_split(dialogue.body_label, at_risk[index], "dialogue line %d" % index)
		dialogue.show_narration("narr%d" % index, at_risk[index])
		_check_no_split(dialogue.body_label, at_risk[index], "narration line %d" % index)
	check(checked_wraps == 2 * at_risk.size(), "every at-risk line wraps without a split name in both boxes (%d of %d)" % [checked_wraps, 2 * at_risk.size()])
	dialogue.queue_free()
	# Equipment detail box (BattleEquipmentView, shared by the status page, item／give views and
	# 整理裝備): every catalog item's description at the box's fixed width.
	var view = preload("res://game/battle/scene/BattleEquipmentView.gd").new()
	root.add_child(view)
	await process_frame
	var catalog: Dictionary = preload("res://game/sim/EquipmentCatalog.gd").items()
	checked_wraps = 0
	var with_names := 0
	for code in catalog:
		var source: String = view.description_text(catalog[code])
		if Array(words).any(func(word): return source.contains(word)):
			with_names += 1
		view.show_description(catalog[code])
		_check_no_split(view.description, source, "equipment %s description" % code)
	check(checked_wraps == catalog.size() and with_names > 0, "every equipment description keeps each name whole (%d of %d, %d name a protected word)" % [checked_wraps, catalog.size(), with_names])
	await process_frame
	check(is_equal_approx(view.description.size.x, view.description.custom_minimum_size.x), "the detail box lays the description out at the width it was wrapped for (%.1f vs %.1f)" % [view.description.size.x, view.description.custom_minimum_size.x])
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
