extends RefCounted
## The original damage／hit random stream: generator 0x458c10, rand(n) 0x458c80 and the
## damage words 0x4c3044／0x4c3040 behind 0x42c720／0x42c780. One state per campaign, kept in
## the loop under LOOP_KEY and in the campaign carry: every exchange (counter gate, hit,
## damage, critical, weapon effects, experience), cast, item effect and turn-end recovery
## draws from it; new game seeds it once as [t, ~t] (0x42ca47), the save keeps it (file
## offsets 0x38／0x3c), loading continues the same sequence.
## A state is [word0, word1], two unsigned 32-bit ints (JSON-exact). Shifts never see a
## negative operand (Godot debug builds reject them), so the arithmetic shift is spelled out.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md; remake-invented (loop_source Callable plumbing; bound < 0 requests the raw 0x42c720 draw)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const MASK := 0xffffffff
const LOOP_KEY := "damage_rng"


static func valid(state: Variant) -> bool:
	if not state is Array or state.size() != 2: return false
	for word in state:
		if typeof(word) != TYPE_INT or word < 0 or word > MASK: return false
	return true


## A saved / carried state, JSON floats accepted; [] when it is not two exact u32 words.
static func from_words(value: Variant) -> Array:
	if not value is Array or value.size() != 2: return []
	var words: Array = []
	for word in value:
		if typeof(word) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(word)) or word != int(word) or word < 0 or word > MASK: return []
		words.append(int(word))
	return words


## New game (0x42ca47): word0 = t, word1 = ~t. The remake's t is the loop seed (clock in the
## product, HSL_RNG_SEED headless).
static func seeded(seed: int) -> Array:
	return [seed & MASK, (~seed) & MASK]


static func _sar(word: int, count: int) -> int:
	if count == 0: return word
	var shifted := word >> count
	if word & 0x80000000: shifted |= (MASK << (32 - count)) & MASK
	return shifted


## 0x458c10: returns {"state", "value"} with the raw u32 draw.
static func raw(state: Array) -> Dictionary:
	var a1: int = (int(state[0]) + 1) & MASK
	var b1: int = (int(state[1]) - 1) & MASK
	var k := b1 & 31
	var a2 := (_sar(a1, (32 - k) & 31) + ((a1 << k) & MASK)) & MASK
	var k2 := a2 & 31
	var b2 := (((b1 << ((32 - k2) & 31)) & MASK) + _sar(b1, k2)) & MASK
	return {"state": [a2, b2], "value": (a2 + b2) & MASK}


## 0x458c80 on a signed 32-bit bound: 0 returns 0 without drawing; bounds up to 0xffff
## (negative ones included) take (r & 0xffff) idiv n; larger bounds r mod n unsigned.
static func rand(state: Array, bound: int) -> Dictionary:
	var n := bound & MASK
	if n > 0x7fffffff: n -= 0x100000000
	if n == 0: return {"state": state.duplicate(), "value": 0}
	var step := raw(state)
	var value: int = int(step["value"])
	step["value"] = (value & 0xffff) % absi(n) if n <= 0xffff else value % n
	return step


static func advance(state: Array, count: int) -> Array:
	var current := state.duplicate()
	for _index in range(count):
		current = raw(current)["state"]
	return current


## One draw on the loop's stream, written back at once. The Callable contract of the rule
## modules: bound > 0 is rand(bound), 0 is rand(0) (no advance), bound < 0 the raw draw.
static func loop_draw(loop: Dictionary, bound: int) -> int:
	var step := raw(loop[LOOP_KEY]) if bound < 0 else rand(loop[LOOP_KEY], bound)
	loop[LOOP_KEY] = step["state"]
	return int(step["value"])


## The rng Variant the combat and skill rules take, bound to this loop dictionary.
static func loop_source(loop: Dictionary) -> Callable:
	return func(bound: int) -> int: return loop_draw(loop, bound)
