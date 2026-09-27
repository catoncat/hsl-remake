extends RefCounted
## The original global random stream: the same generator 0x458c10 and rand(n) 0x458c80 as
## the damage stream (DamageRandomStream supplies the arithmetic), on its own words
## 0x4795d4／0x4795d8. The first draw of the process seeds it from the clock (0x458c10 →
## 0x457830 t = GetTickCount − [0x4c2310]; 0x458bb0 stores [t, t ^ 0xe54a231c] and sets the
## flag 0x4c1e8c); nothing saves it. AI decisions, NPC opening and reinforcement level
## adjustment (0x40e870), random positions and the other script／world rolls draw from it.
##
## One live state per process (`session`), carried by the running battle's loop under
## LOOP_KEY while the loop's rule functions draw from it: a battle adopts the session state
## when it is created, every scene write hands the loop's words back (`remember`), a
## checkpoint load keeps the live words instead of the saved ones (BattleCheckpoint), and a
## campaign carry never holds them. So loading a save repeats the damage stream (saved) but
## not the AI's choices (this stream moved on), as in the original.
## A state is [word0, word1], two unsigned 32-bit ints (JSON-exact).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: remake-invented (the session holder and loop key plumbing; HSL_RNG_SEED stands in for the clock headless)
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const MASK := 0xffffffff
const LOOP_KEY := "global_rng"
## The words' static initial values in the data section (never drawn from: the first draw
## seeds them from the clock).
const STATIC_STATE := [0x12345678, 0x87654321]
## 0x458c20: the lazy seed stores [t, t ^ SEED_XOR].
const SEED_XOR := 0xe54a231c
## Headless runs take the clock's place from this variable (the same one the battle scene
## seeds the damage stream from).
const SEED_ENV := "HSL_RNG_SEED"

## The process's live stream; [] until the first use seeds it.
static var _session: Array = []


static func valid(state: Variant) -> bool:
	return DamageRandomStream.valid(state)


static func from_words(value: Variant) -> Array:
	return DamageRandomStream.from_words(value)


## 0x458c10's lazy seed branch for clock value t.
static func seeded(seed: int) -> Array:
	return [seed & MASK, (seed ^ SEED_XOR) & MASK]


static func raw(state: Array) -> Dictionary:
	return DamageRandomStream.raw(state)


static func rand(state: Array, bound: int) -> Dictionary:
	return DamageRandomStream.rand(state, bound)


static func advance(state: Array, count: int) -> Array:
	return DamageRandomStream.advance(state, count)


## One draw on the loop's stream, written back at once; the DamageRandomStream Callable
## contract (bound > 0 rand(bound), 0 no advance, < 0 the raw draw).
static func loop_draw(loop: Dictionary, bound: int) -> int:
	var step := raw(loop[LOOP_KEY]) if bound < 0 else rand(loop[LOOP_KEY], bound)
	loop[LOOP_KEY] = step["state"]
	return int(step["value"])


## The rng Variant the AI and script rules take, bound to this loop dictionary.
static func loop_source(loop: Dictionary) -> Callable:
	return func(bound: int) -> int: return loop_draw(loop, bound)


## The clock value t of a fresh process stream: HSL_RNG_SEED when a headless run names one,
## else the clock.
static func session_seed() -> int:
	if DisplayServer.get_name() == "headless" and OS.get_environment(SEED_ENV).is_valid_int():
		return int(OS.get_environment(SEED_ENV))
	return Time.get_ticks_msec()


## The live process stream (a copy), seeded on first use.
static func session() -> Array:
	if not valid(_session):
		_session = seeded(session_seed())
	return _session.duplicate()


## A scene write hands the running loop's words back to the process stream.
static func remember(loop: Dictionary) -> void:
	if valid(loop.get(LOOP_KEY)):
		_session = (loop[LOOP_KEY] as Array).duplicate()


## One draw straight on the process stream (world map and town rolls, outside a battle loop).
static func session_draw(bound: int) -> int:
	var state := session()
	var step := raw(state) if bound < 0 else rand(state, bound)
	_session = step["state"]
	return int(step["value"])


## Forget the process stream: the next use seeds it again (test harness: one battle's
## stream must not depend on the battles an earlier suite played in the same process).
static func reset_session() -> void:
	_session = []
