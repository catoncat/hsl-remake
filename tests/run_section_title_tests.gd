extends "res://tests/support/TestSuite.gd"
## actShowSectionName title card (OpeningCinematics; original_tick_counts.md §2): the
## 0x452f32 sub-state machine tick by tick, the two drawn layers (subtractive LEVELSEC band
## stretched vertically, WORD name cross-faded) and that every registered scene's title card
## has its art and plays through this one path.

const Cinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const Coordinator = preload("res://game/battle/runtime/BattleOpeningCoordinator.gd")
const UISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const CAMPAIGN := "res://content/battles/campaign.json"
const ZOOM_ONE := 0x10000


func _init() -> void:
	tag = "SECTION_TITLE_TESTS"


func run() -> void:
	_sub_state_ticks()
	_skip_ticks()
	_view_layers()
	_every_title_card()


func _state(tick: int, skip_hold_tick: int = 0) -> Dictionary:
	return Cinematics.section_title_state_at(tick, skip_hold_tick)


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
	_assert_eq(Coordinator.SECTION_TITLE_IN_TICKS, 159, "the coordinator's entry length is the state machine's")
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
	_expect(582, Cinematics.TITLE_SUB_DONE, 0, 0, 0x76000, "sub-state 7 hands the VM on")
	_assert_eq(int(_state(582)["tick"]), 582, "the card lasts 582 ticks unskipped")
	_assert_eq(int(_state(9999)["tick"]), 582, "the machine stops after sub-state 7")
	_assert_eq(Coordinator.SECTION_TITLE_IN_TICKS + Coordinator.SECTION_TITLE_HOLD_TICKS + Coordinator.SECTION_TITLE_OUT_TICKS, 582, "the coordinator waits the same 582 ticks")
	_assert_eq(Coordinator.SECTION_TITLE_OUT_TICKS, 582 - 479, "the coordinator's exit length is the state machine's")


## Only sub-state 4 reads the key／click; the tick that sees it ends the hold.
func _skip_ticks() -> void:
	var early := Cinematics.section_title_new_state()
	for tick in 159:
		Cinematics.section_title_step(early, true)
	_assert_eq([int(early["sub"]), int(early["tick"])], [4, 159], "input on every entry tick does not shorten the entry")
	_expect(160, 5, 16, 16, ZOOM_ONE, "a key on the first hold tick ends the hold at once", 1)
	_assert_eq(int(_state(9999, 1)["tick"]), 263, "first-hold-tick skip: 159 + 1 + 103 = 263 ticks")
	_assert_eq(int(_state(9999, 100)["tick"]), 159 + 100 + 103, "a key on hold tick 100 leaves the 103-tick exit")
	_expect(160 + 25, 5, 16, 8, ZOOM_ONE, "skipped exit: name level 8 on the 25th exit tick", 1)
	var late := _state(479)
	Cinematics.section_title_step(late, true)
	_assert_eq([int(late["sub"]), int(late["name_level"])], [5, 16], "input after the hold is ignored by the exit ramp")


func _view_layers() -> void:
	var name_texture: Texture2D = load("res://content/imported/hsl/chapter01/battle051/section_title.png")
	var band_record: Dictionary = UISkin.data()["assets"][Cinematics.TITLE_BAND_ASSET]
	_assert_eq(band_record["source_member"], "SHAPE\\LEVELSEC.SHP", "the band is the shape 0x451818 loads")
	_assert_eq(band_record["draw_origin"], [320.0, 104.0], "LEVELSEC origin is its centre")
	var band_origin := Vector2(float(band_record["draw_origin"][0]), float(band_record["draw_origin"][1]))
	var view := Cinematics.build_section_title_view(name_texture, UISkin.texture(Cinematics.TITLE_BAND_ASSET), band_origin)
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
		Cinematics.apply_section_title_state(view, _state(int(row[0])))
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
