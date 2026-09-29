extends RefCounted
## The item description box (0x430710) and read-only use previews／receipts.
## provenance:
##   strings: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (description box 0x430710 case 0／1, range 0x430680 with the half wave 0x17 drawn as ∼)
##   strings: remake-invented (the OPT-GUIDE＝提示 prose rows; use previews and receipts, whose
##     effect values are the settled receipt's)
##   strings: static-derived docs/evidence_packets/static_reverse/original_item_actions.md (0 HP／MP number)
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const BattleEquipmentView = preload("res://game/battle/scene/BattleEquipmentView.gd")

## 0x43088d permanent fields in ITEM order +0x50…+0x70, each RESOURCE name then 625 永久.
const PERMANENT_NAMES := [["attack_power","攻擊力"],["magic_attack_power","魔擊力"],["defense","防禦力"],["speed","敏捷度"],
	["resist_0","抗土"],["resist_1","抗水"],["resist_2","抗風"],["resist_3","抗火"],["resist_4","抗心靈"]]
## ITEM+0xa0 cure bits 0x80000000／0x40000000／0x20000000／0x10000000 and their sentences.
const CURE_SENTENCES := [["cure_poison","治療中毒"],["cure_no_magic","解除魔法封印"],["cure_paralysis","解除痲痺狀態"],["cure_weaken","解除衰弱效果"]]

## The description box lines of a bag／loot／shop row, as 0x430710 builds them ("#" breaks a line):
## types 2..6 are the equipment board's (BattleEquipmentView); type 0 (0x4307dd) is the name,
## 311 重要物品 and the ITEM+0x88 RESOURCE string (`explain`; 197 無特殊屬性 when 0), or the name and
## 197 without the 0x8000000 flag; type 1 (0x43088d) is the name, 79 可使用, one value row (restore,
## then permanent +0x50…+0x70, then local +0x74 攻擊力／+0x7c 防禦力, one space 0x476c74 apart)
## and one flag row. `details` is the items.json row, `definition` the consumable's. The remake's
## explanatory rows follow only under OPT-GUIDE＝提示.
static func description_lines(details: Dictionary, definition: Dictionary = {}) -> Array:
	var type_code := int(details.get("type_code", 1))
	if type_code in range(2, 7):
		return Array(BattleEquipmentView.description_lines(details))
	var lines: Array = [str(details.get("name", ""))]
	if type_code == 0:
		if details.get("important", false): lines.append_array(["重要物品", str(details.get("explain", "無特殊屬性"))])
		else: lines.append("無特殊屬性")
		return lines
	lines.append("可使用")
	var values: Array[String] = []
	var restore := restore_row(definition)
	if restore != "": values.append(restore)
	var permanent: Dictionary = definition.get("permanent", {})
	for pair in PERMANENT_NAMES:
		if permanent.has(pair[0]): values.append(pair[1] + "永久" + range_text(permanent[pair[0]]))
	for pair in [["local_attack","攻擊力"],["local_defense","防禦力"]]:
		var limits: Array = definition.get(pair[0], [])
		if limits.size() == 2: values.append(pair[1] + range_text(limits))
	if not values.is_empty(): lines.append(" ".join(values))
	var flags := _flag_row(details, definition)
	if flags != "": lines.append(flags)
	if not GameOptions.is_original("OPT-GUIDE"): lines.append_array(hint_rows(details, definition))
	return lines

## 0x430680: the first word signed (0x45b6de flag 0x80000006), then when the second differs the
## half wave 0x17 (∼) and the second's magnitude.
static func range_text(limits: Array) -> String:
	var first := int(limits[0])
	var second := int(limits[1]) if limits.size() > 1 else first
	return "%+d" % first + ("" if second == first else "∼%d" % absi(second))

## The ITEM+0xa0 row: 0x8000000 311 alone; else the keep-normal bit (bl & 0x80) or all four cure
## bits 242 alone; else the cure sentences present, one space apart.
static func _flag_row(details: Dictionary, definition: Dictionary) -> String:
	if details.get("important", false): return "重要物品"
	var cures := CURE_SENTENCES.filter(func(pair): return int(definition.get(pair[0], 0)) == 1)
	if (int(details.get("status_effect_flags", 0)) & 0x80) != 0 or cures.size() == CURE_SENTENCES.size():
		return "回復人物正常狀態"
	return " ".join(PackedStringArray(cures.map(func(pair): return pair[1])))

## The remake's explanatory rows of a type 1 item (OPT-GUIDE＝提示 only; the original box has none
## of them), after the 0x43088d rows; a full cure (「回復人物正常狀態」) gets no keep-others row.
static func hint_rows(details: Dictionary, definition: Dictionary) -> Array[String]:
	var full_cure := _flag_row(details, definition) == "回復人物正常狀態"
	var rows: Array[String] = []
	for pair in CURE_SENTENCES:
		if not full_cure and int(definition.get(pair[0], 0)) == 1:
			rows.append("只解除所列狀態，保留其他狀態")
			break
	if not (definition.get("local_attack", []) as Array).is_empty() or not (definition.get("local_defense", []) as Array).is_empty():
		rows.append("增益持續3回；已有同類增益時只延長3回，上限9回")
	for key in definition.get("permanent", {}):
		rows.append("提升原始抗性；原始值上限80，裝備另計" if str(key).begins_with("resist_") else "不改力量／反應／精神／體質；卸裝仍保留")
	return rows

## The restore row as 0x430710 case 1 builds it: RESOURCE 202 生命／203 魔法 with the signed value
## (0x45b6de flag 0x80000000), RESOURCE 624 氣力 in bar cells (value/20, one decimal only when
## the remainder is not 0, then RESOURCE 1201 格), one space (0x476c74) between the parts.
static func restore_row(item: Dictionary) -> String:
	var parts: Array[String] = []
	if int(item.get("heal_hp",0)) != 0: parts.append("生命%+d" % int(item["heal_hp"]))
	if int(item.get("heal_mp",0)) != 0: parts.append("魔法%+d" % int(item["heal_mp"]))
	var stamina := int(item.get("restore_stamina",0))
	if stamina != 0:
		parts.append("氣力%+d%s格" % [stamina / 20, "" if stamina % 20 == 0 else ".%d" % ((stamina % 20) * 10 / 20)])
	return " ".join(parts)

static func preview(effect: Dictionary, item: Dictionary) -> String:
	if not effect.get("ok",false):
		return _no_effect(item) if effect.get("reason") == "item_has_no_effect" else "目前無法使用"
	# A spending preview (the original uses an item on a full target too).
	if not effect.get("useful", true): return _no_effect(item) + "；使用仍會消耗"
	var rows: Array[String] = []
	for row in effect.get("permanent_proposals",[]):
		rows.append("永久%s +%d%s" % [PermanentCapabilityRules.LABELS[row["kind"]],row["low"],"～%d"%int(row["high"]) if row["low"]!=row["high"] else ""])
		if str(row["kind"]).begins_with("resist_"): rows.append("原始值 %d → %d（裝備與職業另計）" % [row["before_raw"],mini(80,int(row["before_raw"])+int(row["high"]))])
	for pair in [["restored_hp","HP"],["restored_mp","MP"],["restored_stamina","氣力"]]:
		if int(effect.get(pair[0],0)) > 0: rows.append("回復 %d %s" % [int(effect[pair[0]]),pair[1]])
	for row in effect.get("stat_proposals",[]):
		rows.append("%s +%d～%d，持續3回" % [StatEnhancementRules.LABELS[row["kind"]],row["low"],row["high"]] if row["roll_required"] else "%s +%d保持，延長至%d回" % [StatEnhancementRules.LABELS[row["kind"]],int(row["before_word"]) >> 16,row["duration"]])
	if rows.is_empty(): return _preview_fallback(item)
	return "\n".join(rows)

## A useful proposal with no value rows (a cure) previews the consumable's own effect rows.
static func _preview_fallback(item: Dictionary) -> String:
	var hints := not GameOptions.is_original("OPT-GUIDE")
	var rows: Array[String] = []
	var restore := restore_row(item)
	if restore != "": rows.append(restore)
	for pair in [["cure_poison","中毒"],["cure_paralysis","麻痺"],["cure_no_magic","禁魔"],["cure_weaken","衰弱"]]:
		if int(item.get(pair[0],0)) == 1: rows.append("解除"+pair[1]+("；保留其他狀態" if hints else ""))
	for pair in [["local_attack","攻擊"],["local_defense","防禦"]]:
		var limits: Array = item.get(pair[0],[])
		if limits.size() == 2:
			rows.append("%s +%d～%d，持續3回" % [pair[1],int(limits[0]),int(limits[1])])
			if hints: rows.append("已有同類增益時只延長3回，上限9回")
	for key in item.get("permanent",{}):
		var limits: Array = item["permanent"][key]
		rows.append("永久%s +%d%s" % [PermanentCapabilityRules.LABELS[key],int(limits[0]),"～%d"%int(limits[1]) if limits[0]!=limits[1] else ""])
		if hints: rows.append("提升原始抗性；原始值上限80，裝備另計" if key.begins_with("resist_") else "不改力量／反應／精神／體質；卸裝仍保留")
	return "\n".join(rows)

static func _no_effect(item: Dictionary) -> String:
	if not item.get("permanent",{}).is_empty(): return "原始抗性已達上限80"
	if int(item.get("restore_stamina",0)) > 0: return "氣力已滿"
	if not item.get("local_attack",[]).is_empty() or not item.get("local_defense",[]).is_empty(): return "同類增益已達9回"
	for pair in [["cure_poison","中毒"],["cure_paralysis","麻痺"],["cure_no_magic","禁魔"],["cure_weaken","衰弱"]]:
		if int(item.get(pair[0],0)) == 1: return "沒有需要解除的"+pair[1]
	return "資源已滿"

static func feedback(receipt: Dictionary) -> String:
	var rows: Array[String] = []
	for effect in receipt.get("permanent_effects",[]): rows.append("永久%s +%d" % [PermanentCapabilityRules.LABELS[effect["kind"]],int(effect["amount"])])
	for pair in [["cured_poison","已解毒"],["cured_paralysis","麻痺解除"],["cured_no_magic","禁魔解除"],["cured_weaken","衰弱解除"]]:
		if receipt.get(pair[0],false): rows.append(pair[1])
	# State108 (0x444ac9) floats an HP／MP number whenever 0x409e40 wrote one, 0 on a full target.
	var numbers: Dictionary = receipt.get("heal_numbers",{})
	for pair in [["restored_hp","HP","hp"],["restored_mp","MP","mp"],["restored_stamina","氣力",""]]:
		if int(receipt.get(pair[0],0)) > 0 or int(numbers.get(pair[2],-1)) == 0: rows.append("%d %s" % [int(receipt[pair[0]]),pair[1]])  # no sign glyph, as defProcShowNumber
	for effect in receipt.get("stat_effects",[]):
		rows.append("%s +%d · %s%d回" % [StatEnhancementRules.LABELS[effect["kind"]],effect["after_power"],"" if effect["sampled"] else "延至",effect["duration"]])
	return "\n".join(rows)
