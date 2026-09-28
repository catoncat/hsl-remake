extends Node2D
## Transient map receiver bars and amount: the cast routine 0x442a90 takes its receivers one
## at a time. Each gets 0x43b3f0's small HP／MP bars (the item-use pair: BAR_HP4 frame, BAR_HP5／
## BAR_HP6 fills, live "cur/max" beside each) for 24 ticks with the HP before the hit; then
## 0x40b8d0 applies the damage — the bar's live read switches to the HP after it and 0x40aba0
## spawns the number at the target's (x, y − 0x34): a hit's red kind-0 number (NUM100..109
## revealed digit by digit, 10 ticks per digit + 34, no rise), a miss's NUM513 MISS (level 16
## for 16 ticks, then fading to tick 46, rising 1 px every other tick), both through
## ResultNumberFloater. The bars go 40 ticks later (a kill first waits 30 ticks, then 40 + 8
## for eff_proc_Local, 40 + 16 for Global) and the next receiver's bars start; the numbers stay.
## One bar slot ([0x4c1cc8]): never two receivers' bars at once. Before every receiver after the
## first the routine glides the camera to it and waits there (states 9／0x19 call 0x43bf30 each
## tick and return until it reports arrival); eff_proc_Local then builds the spell's effect on
## that receiver again (0x443087 → 0x423a20 at its (+4, +8)) and its bars start once the effect
## is done — the remake starts them at the replay's impact tick, as for the first receiver. A
## hurt receiver enters the map hit state 0x407230 on its damage tick (0x40b8d0 → 0x40aa80 →
## 0x40b831); a killed one is marked dead (+0x80 |= 0x8000000, 0x4431a0) 30 ticks later, and
## its death (last words, stretch) runs beside the rest of the bars (`death_released`).
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_magic_damage.md
##     (0x442dd3／0x4430af → 0x43b3f0 → 0x43ace0／0x43ad30; 0x442ea1／0x44323a → 0x43b4c0)
##   layout: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (bar place (x − 21, min(y + 8, map height − 36)), MP 16 below, cur/max at (+44, −6))
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json (BAR_HP4..6)
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_magic_damage.md
##     (+0x9c 24 before the damage, 40 after; a kill's +0x9e 30, then +8 Local／+16 Global)
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_script_camera_scroll.md
##     (0x43bf30 battle step before each later receiver)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ResultNumberFloater = preload("res://game/battle/scene/ResultNumberFloater.gd")
const ItemBars = preload("res://game/battle/scene/BattleItemUsePresentation.gd")
const MapHitState = preload("res://game/battle/scene/MapHitState.gd")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const SkillEffectScriptPlayer = preload("res://game/battle/scene/SkillEffectScriptPlayer.gd")
## The magic keys whose receivers this relay presents (BattlePresentation._present_impact).
const KEYS := ["wind", "fire", "water"]
## 0x40aba0／0x40ac24: the magic channel spawns its number at (target x, target y − 0x34).
const NUMBER_OFFSET := Vector2(0, -0x34)
## 0x442a90 states 9／0x1b: +0x9c = 24 ticks of the bar before 0x40b8d0 applies the damage and
## spawns the number; states 10／0x1c: +0x9c = 40 more, then 0x43b4c0 drops the bars.
const BEFORE_TICKS := 24
const NUMBER_TICKS := BEFORE_TICKS
const AFTER_TICKS := 40
const BAR_TICKS := BEFORE_TICKS + AFTER_TICKS
## A kill (live HP ≤ 0 after 0x40b8d0): +0x9e = 30 ticks before the death mark (0x4431a0), and
## +0x9c grows by 8 (eff_proc_Local, 0x443143) or 16 (Global, 0x442e6f).
const KILL_WAIT_TICKS := 30
const KILL_EXTRA_LOCAL := 8
const KILL_EXTRA_GLOBAL := 16
var entries: Array[Dictionary] = []
var elapsed := 0.0
## OPT-PACE (docs/OPTIONS.md), read once per begin: the multiplier on the clock (Timing.PACE_MAP).
var pace := 1.0
var _art: Dictionary = {}
var _runtime: WeakRef = weakref(null)
## eff_proc_Local's effect timeline, replayed on each later receiver ({} for Global or none).
var _replay: Dictionary = {}
var _effect: SkillEffectScriptPlayer


## `effect_timeline`: the cast's compiled effect (SkillEffectScriptPlayer), replayed on every
## receiver after the first when the spell is eff_proc_Local.
func begin(strike: Dictionary, runtime: Node, effect_timeline: Dictionary = {}) -> void:
	finish()
	_runtime = weakref(runtime)
	pace = float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0))
	if _art.is_empty():
		var assets: Dictionary = BattleUISkin.data()["assets"]
		for key in ["bar_hp4", "bar_hp5", "bar_hp6"]:
			_art[key] = {"texture": load(str(assets[key]["res_path"])), "origin": Vector2(float(assets[key]["draw_origin"][0]), float(assets[key]["draw_origin"][1]))}
	var world_height := 1e9
	if runtime.get("map_config") != null: world_height = float(runtime.map_config.world_size.y)
	var global := _global(strike, runtime)
	_replay = {} if global else effect_timeline
	for hit in strike.get("affected_targets", [strike]):
		var actor = runtime.actor_node_for_unit(str(hit["defender_id"]))
		if actor == null: continue
		var unit: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, str(hit["defender_id"]))
		unit.merge(hit.get("defender_before", {}), true)
		# 0x43b3f0: Bar_HP at (x − 21, min(y + 8, map height − 36)), Bar_MP 16 px under it.
		var bar_world: Vector2 = actor.position + ItemBars.BAR_OFFSET
		bar_world.y = minf(bar_world.y, world_height - ItemBars.BAR_BOTTOM_MARGIN)
		var panel := Node2D.new()
		panel.position = runtime.world_to_logical_position(bar_world)
		add_child(panel)
		var bars: Array[Dictionary] = [{"fill": "bar_hp5", "value": int(unit["hp"]), "max": int(unit["max_hp"])},
			{"fill": "bar_hp6", "value": int(unit.get("mp", 0)), "max": int(unit.get("max_mp", 0))}]
		for index in bars.size():
			var text := BattleUISkin.text(panel, ItemBars.BAR_TEXT_OFFSET + Vector2(0, ItemBars.BAR_PITCH * index), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_SMALL, ItemBars.BAR_TEXT_CELL)
			text.name = "MagicImpactBarText"
			bars[index]["text"] = text
			_set_bar(bars[index], int(bars[index]["value"]))
		panel.draw.connect(_draw_bars.bind(panel, bars))
		var damage := int(hit.get("actual_damage", hit["damage"]))
		# 0x40aba0: the red kind-0 number of a hit, MISS (kind 5) of a miss; hold 0.
		var amount: Node2D = ResultNumberFloater.new()
		amount.name = "DamageDigits" if bool(hit["hit"]) else "MissGlyph"
		amount.clocked = false
		amount.position = runtime.world_to_logical_position(actor.position) + NUMBER_OFFSET
		add_child(amount)
		amount.present("damage" if bool(hit["hit"]) else "miss", damage)
		amount.hide()
		var hp_after := int(hit["defender_hp_after"])
		var life := BAR_TICKS + (KILL_WAIT_TICKS + (KILL_EXTRA_GLOBAL if global else KILL_EXTRA_LOCAL) if hp_after <= 0 else 0)
		# The first receiver's bars start at once; a later one's when its lead is laid (_lead).
		var first := entries.is_empty()
		entries.append({"panel": panel, "bars": bars, "amount": amount, "actor": weakref(actor), "hit": bool(hit["hit"]),
			"hp_after": hp_after, "unit_id": str(hit["defender_id"]), "outcome": hit, "coord": unit.get("coord", Vector2i.ZERO),
			"bar_world": bar_world, "start": 0 if first else -1, "end": life if first else -1, "life": life,
			"float_ticks": amount.life_ticks()})
	elapsed = 0.0
	_process(0.0)


## A later receiver's lead, laid on the tick the previous bars went (0x43b4c0 → 0x4104d0(1)):
## the 0x43bf30 glide to it at the battle step, then (Local) the effect replay; its bars start
## when the glide lands, or at the replay's impact tick.
func _lead(entry: Dictionary, at: int) -> void:
	var controller = _camera()
	var glide := 0
	if controller != null:
		glide = ceili(OriginalTick.ticks(controller.scroll_to(BattleCameraController.focus_centre(controller.grid_cell_center_world(entry["coord"])), BattleCameraController.BATTLE_SCROLL_STEP)))
	entry["glide_end"] = at + glide
	var replay := 0
	if not _replay.is_empty():
		entry["effect_start"] = at + glide
		entry["effect_clip"] = {"effect_timeline": _replay}
		replay = int(_replay.get("impact_tick", 0))
	entry["start"] = at + glide + replay
	entry["end"] = int(entry["start"]) + int(entry["life"])


func _camera() -> RefCounted:
	var runtime: Node = _runtime.get_ref()
	return runtime.camera_controller if runtime != null and "camera_controller" in runtime else null


## Whether the receiver `unit_id` killed by this cast has been marked dead (+0x9e ran out: 30
## ticks after its damage tick, 0x4431a0) — its death may play while later bars run. True when
## no relay holds it.
func death_released(unit_id: String) -> bool:
	for entry in entries:
		if str(entry["unit_id"]) != unit_id or int(entry["hp_after"]) > 0: continue
		return int(entry["start"]) >= 0 and int(OriginalTick.ticks(elapsed)) >= int(entry["start"]) + BEFORE_TICKS + KILL_WAIT_TICKS
	return true


## eff_proc_Global (MAGIC +0x2c = 1, read by 0x409920) takes the 0x442a90 branch whose kill
## adds 16; Local adds 8.
func _global(strike: Dictionary, runtime: Node) -> bool:
	var loop = runtime.get("play_loop")
	if not (loop is Dictionary): return false
	var skill: Dictionary = loop.get(LoopKeys.SKILL_BOOK, {}).get("skills", {}).get(str(strike.get("skill_id", "")), {})
	return str(skill.get("fields", {}).get("effect_proc", "")) == "eff_proc_Global"


## Seconds until every bar and number has gone: the last receiver's bars, or the longest
## number from its receiver's damage tick, whichever ends later.
## A later receiver whose lead is not laid yet counts from the previous bars' end with no glide.
func total_seconds() -> float:
	var last := 0
	var previous_end := 0
	for entry in entries:
		var start := int(entry["start"]) if int(entry["start"]) >= 0 else previous_end + int(_replay.get("impact_tick", 0))
		previous_end = start + int(entry["life"])
		last = maxi(last, maxi(previous_end, start + NUMBER_TICKS + int(entry["float_ticks"])))
	return OriginalTick.seconds(last)


## The longest number among the entries: a red damage number lives 10 ticks per digit + 34,
## MISS 47 (its first tick initialises, then 46).
func float_seconds() -> float:
	var longest := 0
	for entry in entries:
		longest = maxi(longest, int(entry["float_ticks"]))
	return OriginalTick.seconds(longest)


## 0x4364e0's draw branch: the BAR_HP4 frame by its origin, then the fill (BAR_HP5 HP, BAR_HP6
## MP) filled × 39 / max wide (16.16 fixed point, 0x436576..0x4365ae) through 0x4607f9.
func _draw_bars(panel: Node2D, bars: Array[Dictionary]) -> void:
	for index in bars.size():
		var bar: Dictionary = bars[index]
		var at := Vector2(0, ItemBars.BAR_PITCH * index)
		panel.draw_texture(_art["bar_hp4"]["texture"], at - _art["bar_hp4"]["origin"])
		var fill: Texture2D = _art[bar["fill"]]["texture"]
		var maximum := int(bar["max"])
		var width := 0 if maximum <= 0 else (((int(bar["value"]) << 16) / maximum) * fill.get_width()) >> 16
		if width > 0:
			panel.draw_texture_rect_region(fill, Rect2(at, Vector2(width, fill.get_height())), Rect2(Vector2.ZERO, Vector2(width, fill.get_height())))


func _set_bar(bar: Dictionary, value: int) -> void:
	bar["value"] = value
	bar["text"].text = "%d/%d" % [value, int(bar["max"])]


func busy() -> bool:
	return not entries.is_empty()


func _process(delta: float) -> void:
	if not busy(): return
	elapsed += maxf(0.0, delta) * pace
	var tick := int(OriginalTick.ticks(elapsed))
	for index in range(1, entries.size()):
		var previous: int = entries[index - 1]["end"]
		if int(entries[index]["start"]) < 0 and previous >= 0 and tick >= previous:
			_lead(entries[index], previous)
	if elapsed >= total_seconds():
		finish()
		return
	var runtime: Node = _runtime.get_ref()
	var controller = _camera()
	var drawn := false
	for entry in entries:
		var actor: Node2D = entry["actor"].get_ref()
		# The bars and numbers stay on their map points while the camera glides.
		if runtime != null and actor != null:
			entry["panel"].position = runtime.world_to_logical_position(entry["bar_world"])
			entry["amount"].position = runtime.world_to_logical_position(actor.position) + NUMBER_OFFSET
		if entry.has("glide_end") and tick >= int(entry["glide_end"]) and not entry.get("landed", false):
			entry["landed"] = true
			if controller != null and controller.is_scrolling(): controller.finish_scroll()
		if entry.has("effect_clip") and runtime != null and tick >= int(entry["effect_start"]) and tick < int(entry["effect_start"]) + int(_replay.get("complete_tick", 0)):
			drawn = true
			_effect_player().draw(entry["effect_clip"], OriginalTick.seconds(tick - int(entry["effect_start"])), [runtime.grid_cell_center_to_logical_position(entry["coord"])])
		var start := int(entry["start"])
		var local: int = tick - start
		var on := start >= 0 and local >= 0 and tick < int(entry["end"])
		entry["panel"].visible = on
		if start >= 0 and local >= BEFORE_TICKS and not entry.get("after_shown", false):
			# 0x40b8d0 applied the damage: the bar's live read shows the HP after it, and a hurt
			# receiver enters the map hit state this tick (0x40aa80 → 0x40b831 → 0x407230).
			entry["after_shown"] = true
			_set_bar(entry["bars"][0], int(entry["hp_after"]))
			entry["panel"].queue_redraw()
			if runtime != null and MapHitState.hurt(entry["outcome"]):
				MapHitState.begin(runtime, self, str(entry["unit_id"]), pace)
		if start < 0 or local < NUMBER_TICKS:
			entry["amount"].hide()
		else:
			entry["amount"].draw_at(local - NUMBER_TICKS)
		if actor != null and on:
			var brightness := 1.0 + maxf(0, 1 - float(local) / BEFORE_TICKS) if entry["hit"] else 1.0
			actor.modulate = Color(brightness, brightness, brightness)
	if not drawn and _effect != null: _effect.clear()


func _effect_player() -> SkillEffectScriptPlayer:
	if _effect == null:
		_effect = SkillEffectScriptPlayer.new()
		_effect.name = "ReceiverEffect"
		add_child(_effect)
	return _effect


func finish() -> void:
	for entry in entries:
		var actor: Node2D = entry["actor"].get_ref()
		if actor != null: actor.modulate = Color.WHITE
		entry["panel"].queue_free()
		entry["amount"].queue_free()
	entries.clear()
	if _effect != null: _effect.clear()


func _exit_tree() -> void:
	finish()
