extends RefCounted
## Shared presentation schedule in original ticks. Attacker duration comes from the
## compiled ANIMAL dispatch; the receiver phases are the AnimalDefense object's own
## counters; number lifetimes are the defProcShowNumber state machine. Durations are not
## combat rules.
## provenance:
##   timing: resource-derived content/imported/hsl/chapter01/combat_animation/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: remake-invented (OPT-PACE 快／極快 clock multipliers PACE_CUTIN／PACE_MAP; 原版 is × 1.0)
##   timing: provisional
##     (CAST_LEAD_IN stands in for the m_action lead of a magic caster whose m_shape strip is not imported — the
##     imported ones and the 絶技 s_action lead are played by AnimalCastLead)
const OriginalTick = preload("res://game/common/OriginalTick.gd")

## Multiplier on the ordinary cut-in clock. The product plays the attacker's ANIMAL program
## at the original tick rate (1.0). The developer switch HSL_CUTIN_PLAYBACK_SPEED (e.g. 0.4)
## slows the cut-in for frame review; this is its only read site — every module scales
## through Timing.PLAYBACK_SPEED. Unset, empty or invalid values mean 1.0.
const PLAYBACK_SPEED_ENV := "HSL_CUTIN_PLAYBACK_SPEED"
const ORIGINAL_PLAYBACK_SPEED := 1.0
static var PLAYBACK_SPEED: float = _read_playback_speed()


static func _read_playback_speed() -> float:
	var raw := OS.get_environment(PLAYBACK_SPEED_ENV).strip_edges()
	if raw == "":
		return ORIGINAL_PLAYBACK_SPEED
	if not raw.is_valid_float() or float(raw) <= 0.0:
		push_error("%s must be a positive number, got %s; playing at the original speed" % [PLAYBACK_SPEED_ENV, raw])
		return ORIGINAL_PLAYBACK_SPEED
	return float(raw)


## Wall-clock seconds expressed on the cut-in's scaled clock (elapsed × PLAYBACK_SPEED), so
## a visible duration keeps its length whatever the playback speed.
static func scaled(visible_seconds: float) -> float:
	return visible_seconds * PLAYBACK_SPEED

## OPT-PACE 演出節奏 (docs/OPTIONS.md): the multiplier a presentation's own clock runs at, keyed by
## the option value and read once as that presentation starts (the read points multiply their
## frame delta, so 原版 = × 1.0 is the untouched original rate). 快 doubles the cut-in and the map
## cues; 極快 doubles the map cues and runs the close-up hidden at 16× — its impact／release
## signals and the map numbers come in the same order, the close-up is never on screen.
const PACE_CUTIN := {"original": 1.0, "fast": 2.0, "fastest": 16.0}
const PACE_MAP := {"original": 1.0, "fast": 2.0, "fastest": 2.0}
const PACE_HIDDEN_CUTIN := "fastest"

## Receiver phases in ticks of visible time, read from the AnimalDefense object process
## (0x4038a0; the object 0x9b that 0x406eb0 inserts after the attacker's shot). Its own
## clock: the init tick sets phase 0; phase 0 rolls the hit (0x403ef8) and loads the
## counter with 0x1e (0x4038b4); phase 1 counts it down (0x403f13) — the victim stands in
## the neutral pose for 32 ticks — then reloads 0x28 (0x403f29) and branches.
const TARGET_PAUSE_TICKS := 32
## Hit: knockback, hurt pose and the weapon sound at once; phase 2 counts the 40 ticks
## down (0x40424c) and spawns the kind-0 damage number with the object as waiter
## (0x404290, hold 0); phase 3 waits for the number to release it; phase 4 spends one tick
## (0x4042a5, counter already 0) and ends at phase 101.
const HIT_TO_NUMBER_TICKS := 40
## Miss: phase 5 slides the victim 150 px (0x96) with 0x45e91e(step 0x24, distance／4,
## minimum 2) — 14 moving ticks and the arrival tick — phase 6 spends one tick, phase 4
## counts the untouched 0x28 down.
const MISS_SLIDE_TICKS := 15
const MISS_HOLD_TICKS := 40
## The original shows no return-to-neutral pose. Phase 101 (0x404aab) of the last shot of
## an exchange requests the screen transition 0x42dc90(1) = 0x46098f(1): the frame body
## (0x460a06) blends the full-screen black shape at level 1 → 16, one level per tick, over the
## held hurt pose — 16 ticks; when the pending flag clears it hides the defender, leaves the
## cut-in (0x42c3f0(0)) and requests 0x42dca0(1) = 0x4609c0(1): level 16 → 1 over the map,
## another 16 ticks; only then does the parent sequence advance. A shot with a counter or
## extra strike still to come (bit 0x200 set by 0x403860, target alive) skips both halves.
const RECOVERY_TICKS := 16
const CLOSING_LIGHTEN_TICKS := 16
const TRANSITION_LEVELS := 16
## Schedule values live on the cut-in's scaled clock (elapsed × PLAYBACK_SPEED), so a
## visible tick count is multiplied by PLAYBACK_SPEED to keep its wall-clock length.
static var TARGET_PAUSE: float = scaled(OriginalTick.seconds(TARGET_PAUSE_TICKS))
static var RECOVERY: float = scaled(OriginalTick.seconds(RECOVERY_TICKS))
static var CLOSING_LIGHTEN: float = scaled(OriginalTick.seconds(CLOSING_LIGHTEN_TICKS))

## AnimalAttack phase 100 (0x401c20, case 100 at 0x4027ce) on the first shot of an exchange
## (object bit 0x200 clear; a counter or extra-strike shot skips to the program). Sub-state 1
## draws the object's default shape MAGIC\BALL001.SHP (obj_Animal_Attack 154) at the screen
## centre (camera ＋ (320, 240)) with the additive zoom mode 0xc000000, zoom = +0x90 from
## 0x1000 stepped by 0x401060 until ≥ 0xd0001 — 24 draws; then sets zoom 0x120000 (18.0),
## restores the attacker's frame (+0x30 = +0x32), builds the identity-strip text (0x436490
## mode 3) and draws the same shape with the level-blend mode 0x28000000 at level +0x28 =
## 16 → 1, one level per 2 ticks (+0x94 = 0x20002) — 32 draws. No sound call.
const OPENING_ZOOM_TICKS := 24
const OPENING_OVERLAY_TICKS := 32
const OPENING_TICKS := OPENING_ZOOM_TICKS + OPENING_OVERLAY_TICKS
const OPENING_ZOOM_START := 0x1000
const OPENING_ZOOM_LIMIT := 0xd0001
const OPENING_OVERLAY_ZOOM := 0x120000
const OPENING_OVERLAY_LEVEL_TICKS := 2


## 0x401060: the zoom step grows with the current 16.16 zoom.
static func opening_zoom_step(zoom: int) -> int:
	if zoom < 0x4000: return zoom + 0x1000
	if zoom < 0x8000: return zoom + 0x2000
	if zoom < 0x10000: return zoom + 0x4000
	if zoom < 0x20000: return zoom + 0x6000
	if zoom < 0x30000: return zoom + 0x8000
	if zoom < 0x40000: return zoom + 0xa000
	return zoom + 0xe000


## The 24 zoom values the ramp draws, as 16.16 fixed point (0x1000 … 0xc4000).
static func opening_zoom_ramp() -> Array[int]:
	var ramp: Array[int] = []
	var zoom := OPENING_ZOOM_START
	while zoom < OPENING_ZOOM_LIMIT:
		ramp.append(zoom)
		zoom = opening_zoom_step(zoom)
	return ramp


static var OPENING_ZOOM_RAMP: Array[int] = opening_zoom_ramp()


## Blend level (16 = opaque … 1) of the overlay draw at `tick` ticks into the overlay.
static func opening_overlay_level(tick: int) -> int:
	return clampi(TRANSITION_LEVELS - tick / OPENING_OVERLAY_LEVEL_TICKS, 1, TRANSITION_LEVELS)


static func opening_ticks(first_shot: bool) -> int:
	return OPENING_TICKS if first_shot else 0


## Level (1 … 16) of the closing darken at `tick` ticks into it (0x46098f(1): level 1 first).
static func closing_darken_level(tick: int) -> int:
	return clampi(1 + tick, 1, TRANSITION_LEVELS)


## Level (16 … 1) of the closing lighten at `tick` ticks into it (0x4609c0(1): level 16 first).
static func closing_lighten_level(tick: int) -> int:
	return clampi(TRANSITION_LEVELS - tick, 1, TRANSITION_LEVELS)


## The screen transition closes the exchange after this strike: the last shot (no counter or
## extra strike still queued) or a defender left at 0 HP (0x404b4b: HP < 1 → transition).
static func closes_exchange(strike: Dictionary, last_shot: bool) -> bool:
	return last_shot or int(strike.get("defender_hp_after", 1)) <= 0


## Visible ticks between the impact and the recovery shot: 68 ＋ 10 per damage digit on a
## hit (78／88／98), 56 on a miss. ±1 tick: the process order of the number object and the
## defender object within one tick is not read.
static func hurt_hold_ticks(hit: bool, damage: int) -> int:
	if not hit:
		return MISS_SLIDE_TICKS + 1 + MISS_HOLD_TICKS
	return HIT_TO_NUMBER_TICKS + damage_number_release_ticks(damage) + 1


static func hurt_hold(hit: bool, damage: int) -> float:
	return scaled(OriginalTick.seconds(hurt_hold_ticks(hit, damage)))
## Cast_Star lead of the map magic presenter, 1.1 s visible on the scaled clock, for a caster
## without an imported m_shape strip (the original's m_action lead, played by AnimalCastLead
## when the strip is imported, has the same program shape as the s_action lead).
const CAST_LEAD_IN_VISIBLE_SECONDS := 1.1
static var CAST_LEAD_IN: float = scaled(CAST_LEAD_IN_VISIBLE_SECONDS)

## defProcShowNumber (0x408580): after the spawn's hold ticks, an EXP／heal／MP／$／MISS／
## LEVEL UP number (kind 1–6) lives 16 + 15 × 2 = 46 ticks, releases its waiter at tick 32
## and rises 1 px every second tick; a red damage number (kind 0) bounces 10 ticks per
## digit, then holds 18 and counts down 16 single ticks.
const SHOW_NUMBER_TICKS := 46
const SHOW_NUMBER_RELEASE_TICKS := 32
## kind 0 lives 10 per digit ＋ 34 (one hold tick, 18 settle, 15 more ticks after the level first
## drops): 44 ticks for one digit, 54 for two (DamageNumberFloater.life_ticks).
const DAMAGE_NUMBER_BASE_TICKS := 34
const DAMAGE_NUMBER_DIGIT_TICKS := 10
## kind 0 after its bounce: 18 settle ticks (+0x90 = 0x10012), then +0x28 counts 16 → 0 one
## per tick and releases the waiter when it drops below 9 — the 8th of those ticks.
const DAMAGE_NUMBER_SETTLE_TICKS := 18
const SHOW_NUMBER_RELEASE_COUNTDOWN_TICKS := 8
const SHOW_NUMBER_HOLD_TICKS := 1
const SHOW_NUMBER_RISE_PX_PER_TICK := 0.5
const SHOW_NUMBER_SECONDS := OriginalTick.TICK_SECONDS * SHOW_NUMBER_TICKS
## The remake fades a number over the ticks after the original releases its waiter.
const SHOW_NUMBER_FADE_SECONDS := OriginalTick.TICK_SECONDS * (SHOW_NUMBER_TICKS - SHOW_NUMBER_RELEASE_TICKS)
const SHOW_NUMBER_RISE_PX_PER_SECOND := SHOW_NUMBER_RISE_PX_PER_TICK * OriginalTick.TICKS_PER_SECOND


## Ticks from a kind-0 damage number's spawn (hold 0) to the tick it increments its waiter's
## phase word: one hold tick, the digit bounce, the settle ticks, eight countdown ticks.
static func damage_number_release_ticks(amount: int) -> int:
	var digits := str(absi(amount)).length()
	return SHOW_NUMBER_HOLD_TICKS + DAMAGE_NUMBER_DIGIT_TICKS * digits + DAMAGE_NUMBER_SETTLE_TICKS + SHOW_NUMBER_RELEASE_COUNTDOWN_TICKS


## The ordinary cut-in schedule for one strike: `strike` supplies `hit` and `damage` for the
## receiver's hold (an empty strike schedules a one-digit hit); `first_shot` adds the
## attacker's phase-100 opening before the program, `last_shot` (or a killed defender) the
## screen transition after the hurt hold. `opening` is the program's start, `recovery` the
## start of the darken (hurt pose held), `darkened` the start of the lighten over the map.
static func ordinary(actor: Dictionary, strike: Dictionary = {}, first_shot: bool = true, last_shot: bool = true) -> Dictionary:
	# Complete ANIMAL program binding, not a regexp list of frame/delay pairs.
	# Source setup/wait/yield boundaries advance one update per original tick.
	var dispatch: Dictionary = actor["dispatch"]
	var opening := OriginalTick.seconds(float(opening_ticks(first_shot)))
	var duration := opening + OriginalTick.seconds(float(dispatch["complete_updates"]))
	var release_time := opening + OriginalTick.seconds(float(dispatch["release_update"]))
	var impact_time := duration + TARGET_PAUSE
	var hold := hurt_hold(bool(strike.get("hit", true)), int(strike.get("damage", 0)))
	var closing := closes_exchange(strike, last_shot)
	var darkened := impact_time + hold + (RECOVERY if closing else 0.0)
	return {"opening": opening, "release": release_time, "target": duration, "impact": impact_time,
		"recovery": impact_time + hold, "darkened": darkened, "complete": darkened + (CLOSING_LIGHTEN if closing else 0.0)}


static func phase_at(schedule: Dictionary, elapsed: float) -> String:
	for phase in ["opening", "release", "target", "impact", "recovery", "darkened", "complete"]:
		if elapsed < float(schedule[phase]):
			return {"opening": "opening", "release": "windup", "target": "release", "impact": "target_pause", "recovery": "hurt", "darkened": "recovery", "complete": "closing"}[phase]
	return "complete"
