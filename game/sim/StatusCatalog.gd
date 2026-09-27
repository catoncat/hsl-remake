extends RefCounted
## 状态效果目录表：毒／麻痺／封魔／衰弱每种一行。规则与画面文件都查这张表，不再各写状态键。
## 加一种状态：ENTRIES 登记一行；原版某个例程要依次走到它的，再把键插进下面那条例程的顺序表
## （MAGIC_ORDER／WEAPON_ORDER／CURE_ORDER——原版各例程走状态的先后不同，是规则的一部分）。
## 只有带专属规则的状态（毒的回合末扣血、衰弱的力量折算与 0x448840 刷新）才在规则文件里点名键常量。
## Fields of one row:
##   flag             actor +0x24 status_flags bit (status_flags stays the saved field).
##   counter          "required": status_counters always carries the packed word (power << 16 | turns);
##                    "optional": the word is absent while the status is off (0x38 衰弱 word).
##   power            the high word carries a strength (poison damage, weaken attribute loss).
##   blocks_action    a fresh action is skipped while the flag is set (443996／43f47b).
##   expiry           "action_end_countdown": 0x40b910 decrements the low word after each action and
##                    clears the flag at 0 ("" = never expires by itself).
##   expiry_event     the turn-end receipt carries a "<key>_expired" event when it runs out.
##   refresh          applying, curing or expiring it ends in the 0x448840 derived-stat refresh.
##   magic_bit        0x40aa80 function bit that inflicts it (magic／special channel1).
##   immunity_bit     equipment status_effect_flags bit that blocks it (OR 0x80 keep_status_good).
##   capability_bit   PLAYERS status_capability_flags bit mapped onto immunity_bit by 0x448420.
##   weapon_bit       ITEM weapon_effect_flags bit of the 0x409310 ordinary-strike branch.
##   weapon_power     0x406fe0 (lo, hi) power draw of that branch ([0, 0] = no power).
##   cure_magic_bit   0x40aa80 cure branch function bit (support magic).
##   cure_item        ITEM field (0/1) of the consumable that removes it (0x40a2ed..0x40a337).
##   contribution     per-added-turn weight of the status-magic EXP contribution.
##   name             caption name (cut-in, weapon feedback, item and equipment previews).
##   state_word       the one-character 狀態 word of the close-up (RESOURCE 125..128, bit order).
##   cure_label       caption when a cure removes it (and when an expiry_event row runs out);
##                    "無" + name when a cure found none to remove.
##   stronger_label   weapon feedback when a hit only raised its power.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_effects.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_status_application.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_paralysis.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_effects.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_support_magic.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: static-derived docs/evidence_packets/static_reverse/original_field_coverage.md
##     (state_word: 0x434d10 prints RESOURCE 125 毒／126 封／127 痲／128 弱)
##   strings: remake-invented
##     (name, cure_label, stronger_label: captions for effects the original shows no glyph for)
const POISON_KEY := "poison"
const PARALYSIS_KEY := "paralysis"
const NO_MAGIC_KEY := "no_magic"
const WEAKEN_KEY := "weaken"
const ENTRIES := {
	POISON_KEY: {"flag": 1, "counter": "required", "power": true, "blocks_action": false,
		"expiry": "action_end_countdown", "expiry_event": false, "refresh": false,
		"magic_bit": 8, "immunity_bit": 0x800000, "capability_bit": 0x40,
		"weapon_bit": 0x200000, "weapon_power": [16, 32], "cure_magic_bit": 0x400, "cure_item": "cure_poison",
		"contribution": 10, "name": "中毒", "state_word": "毒", "cure_label": "解毒", "stronger_label": "毒效增強"},
	PARALYSIS_KEY: {"flag": 4, "counter": "required", "power": false, "blocks_action": true,
		"expiry": "action_end_countdown", "expiry_event": true, "refresh": false,
		"magic_bit": 4, "immunity_bit": 0x4000000, "capability_bit": 0x800,
		"weapon_bit": 0x100000, "weapon_power": [0, 0], "cure_magic_bit": 0x200, "cure_item": "cure_paralysis",
		"contribution": 10, "name": "麻痺", "state_word": "痲", "cure_label": "麻痺解除", "stronger_label": "麻痺增強"},
	NO_MAGIC_KEY: {"flag": 2, "counter": "required", "power": false, "blocks_action": false,
		"expiry": "action_end_countdown", "expiry_event": false, "refresh": false,
		"magic_bit": 16, "immunity_bit": 0x1000000, "capability_bit": 0x1000,
		"weapon_bit": 0x80000, "weapon_power": [0, 0], "cure_magic_bit": 0x800, "cure_item": "cure_no_magic",
		"contribution": 5, "name": "禁魔", "state_word": "封", "cure_label": "禁魔解除", "stronger_label": "禁魔增強"},
	WEAKEN_KEY: {"flag": 8, "counter": "optional", "power": true, "blocks_action": false,
		"expiry": "action_end_countdown", "expiry_event": false, "refresh": true,
		"magic_bit": 0x1000, "immunity_bit": 0x2000000, "capability_bit": 0x2000,
		"weapon_bit": 0x20000, "weapon_power": [3, 7], "cure_magic_bit": 0x2000, "cure_item": "cure_weaken",
		"contribution": 7, "name": "衰弱", "state_word": "弱", "cure_label": "衰弱解除", "stronger_label": "衰弱增強"},
}
## 0x40aa80 status branches in function-bit order (paralysis 4, poison 8, no_magic 16, weaken 0x1000).
const MAGIC_ORDER := [PARALYSIS_KEY, POISON_KEY, NO_MAGIC_KEY, WEAKEN_KEY]
## 0x409310 weapon branches (0x409240 weaken, 0x409210 no_magic, 0x409110 paralysis, 0x4091b0 poison).
const WEAPON_ORDER := [WEAKEN_KEY, NO_MAGIC_KEY, PARALYSIS_KEY, POISON_KEY]
## 0x40aa80 cure branches after buff/dispel: CureWeaken, CureParalysis, CurePoison, CureNoMagic.
const CURE_ORDER := [WEAKEN_KEY, PARALYSIS_KEY, POISON_KEY, NO_MAGIC_KEY]
## Compile-time copy of every row's weapon_power (a test support script reads it in a const);
## rules read ENTRIES.
const WEAPON_POWER_DOMAIN := {POISON_KEY: ENTRIES[POISON_KEY]["weapon_power"], WEAKEN_KEY: ENTRIES[WEAKEN_KEY]["weapon_power"],
	NO_MAGIC_KEY: ENTRIES[NO_MAGIC_KEY]["weapon_power"], PARALYSIS_KEY: ENTRIES[PARALYSIS_KEY]["weapon_power"]}


## {key: row[field]} over `order` (catalog order when empty), read-only.
static func by_key(field: String, order: Array = []) -> Dictionary:
	var result := {}
	for key in order if not order.is_empty() else ENTRIES.keys():
		result[key] = ENTRIES[key][field]
	result.make_read_only()
	return result


## Keys whose `field` equals `value`, in catalog order.
static func keys_where(field: String, value: Variant) -> Array:
	var result := []
	for key in ENTRIES:
		if ENTRIES[key][field] == value: result.append(key)
	result.make_read_only()
	return result


## OR of the flags of every row whose `field` is true.
static func flag_mask(field: String) -> int:
	var mask := 0
	for key in keys_where(field, true): mask |= int(ENTRIES[key]["flag"])
	return mask


static func row(key: String) -> Dictionary:
	return ENTRIES[key]


static func name_of(key: String) -> String:
	return str(ENTRIES[key]["name"])
