extends RefCounted
## Packed attack/defense enhancement words. Absent inactive slots are intentional.
## resist_up (魔障壁 magicFun_AllUp 0x100): 0x40aa80 sets flag 0x40, adds rand(4)+2 turns to
## +0x48 (cap 9) and rand(14)+7 to the strength word +0x4a (cumulative, cap 20); 0x448840 adds
## that strength to all five live resistances (cap 80); 0x40b910 expires it with a refresh.
## 退魔 (0x4000) clears only the 0x10/0x20 words, never this one (static-derived).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_stat_magic.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const FLAGS := {"attack_up": 0x10, "defense_up": 0x20, "resist_up": 0x40}
const LABELS := {"attack_up": "攻擊", "defense_up": "防禦", "resist_up": "抗性"}
const RESIST_MIN := 7
const RESIST_MAX := 20

static func input_error(actor: Dictionary) -> String:
	var words: Variant = actor.get("status_counters")
	if not words is Dictionary: return "missing_stat_enhancement_state"
	var flags := SkillResourceRules._integer(actor.get("status_flags"))
	if flags < 0: return "invalid_stat_enhancement_flags"
	for key in FLAGS:
		var value := SkillResourceRules._integer(words.get(key, 0))
		if value < 0 or value > 0xffffffff: return "invalid_" + key + "_counter"
		if ((flags & FLAGS[key]) != 0) != (value != 0): return "inconsistent_" + key + "_state"
		if value != 0:
			if (value & 65535) < 1 or (value & 65535) > 9: return "invalid_" + key + "_duration"
			var magnitude := value >> 16
			if key == "resist_up":
				if magnitude < RESIST_MIN or magnitude > RESIST_MAX: return "invalid_" + key + "_power"
				continue
			# Items262/263 start at5..10 and share these words with magic; a later
			# spell averages with that power. Spell normalization itself is unchanged.
			if magnitude < 5 or magnitude > (96 if key == "attack_up" else 100): return "invalid_" + key + "_power"
	return ""

static func word(actor: Dictionary, key: String) -> int:
	return int(actor.get("status_counters", {}).get(key, 0))

static func power(actor: Dictionary, key: String) -> int:
	return word(actor, key) >> 16

static func normalize_power(kind: String, value: int) -> int:
	if kind == "resist_up": return value # 0x40b24a: rand(14)+7, no folding; the cap applies after summing
	var minimum := 16 if kind == "attack_up" else 12
	var maximum := 96 if kind == "attack_up" else 100
	var period := 8 if kind == "attack_up" else 10
	# Source wraps high values into the top band and lifts low values by whole
	# minimum-sized steps. A plain clamp gives different original results.
	if value > maximum: value -= period * ((value - (maximum - period + 1)) / period)
	if value < minimum: value += minimum * ((2 * minimum - 1 - value) / minimum)
	return value

static func merge_word(before: int, duration: int, strength: int) -> int:
	var old_power := before >> 16
	var after_power := maxi(old_power, (old_power + strength) / 2) if old_power > 0 else strength
	return (after_power << 16) | mini(9, (before & 65535) + duration)

## 0x40b21b..0x40b274: turns add (cap 9); strength = min(20, old + sampled) — not averaged.
static func merge_resist_word(before: int, duration: int, strength: int) -> int:
	return (mini(RESIST_MAX, (before >> 16) + strength) << 16) | mini(9, (before & 65535) + duration)

static func item_word(before: int, sampled_strength: int) -> int:
	#40a134/40a17b read the low WORD, not the whole packed value. Existing
	#strength stays intact even when it was granted by a stronger spell.
	if (before & 65535) >= 9: return before
	return ((before >> 16 if before != 0 else sampled_strength) << 16) | mini(9,(before & 65535)+3)

static func apply(actor: Dictionary, key: String, duration: int, strength: int) -> Dictionary:
	var next := actor.duplicate(true)
	var before := word(actor, key)
	var after := merge_resist_word(before, duration, strength) if key == "resist_up" else merge_word(before, duration, normalize_power(key, strength))
	next["status_counters"][key] = after
	next["status_flags"] = int(next["status_flags"]) | int(FLAGS[key])
	# Contribution weight per added turn: DefUp／AttUp 2 (0x40b04a／0x40b174), AllUp 3 (0x40b24c).
	return {"actor": next, "effects": [{"kind": key, "before_word": before, "after_word": after,
		"before_power": before >> 16, "after_power": after >> 16, "duration": after & 65535}],
		"contribution": ((after & 65535) - (before & 65535)) * (3 if key == "resist_up" else 2)}

## 退魔 (0x40b29d): only the attack (0x10／+0x40) and defense (0x20／+0x44) words are cleared.
const DISPELLED := ["attack_up", "defense_up"]

static func dispel(actor: Dictionary) -> Dictionary:
	var next := actor.duplicate(true)
	var effects: Array = []
	var contribution := 0
	for key in DISPELLED:
		var before := word(actor, key)
		if before == 0: continue
		next["status_counters"].erase(key)
		next["status_flags"] = int(next["status_flags"]) & ~int(FLAGS[key])
		contribution += ((before & 65535) + 1) * 12
		effects.append({"kind": key, "before_word": before, "after_word": 0,
			"before_power": before >> 16, "after_power": 0, "duration": 0})
	return {"actor": next, "effects": effects, "contribution": contribution}

static func after_action(flags: int, words: Dictionary) -> Dictionary:
	var result := words.duplicate(true)
	var expired: Array = []
	for key in FLAGS:
		var value := int(result.get(key, 0))
		if value == 0: continue
		if (value & 65535) == 1:
			result.erase(key)
			flags &= ~int(FLAGS[key])
			expired.append(key)
		else: result[key] = value - 1
	return {"flags": flags, "words": result, "expired": expired}

static func descriptions(actor: Dictionary) -> Array:
	var rows: Array = []
	for key in FLAGS:
		var value := word(actor, key)
		if value: rows.append("%s +%d（剩餘%d回；本回最後行動結束時計時）" % [LABELS[key], value >> 16, value & 65535])
	return rows
