extends RefCounted
## Read-only descriptions from validated item proposals and committed receipts.
## provenance:
##   strings: remake-invented (receipt descriptions; effect values are the settled receipt's)
##   strings: static-derived docs/evidence_packets/static_reverse/original_item_actions.md (0 HP／MP number)
##   strings: static-derived docs/evidence_packets/static_reverse/original_getitem_window.md
##     (0x436d70 box: 解除／永久 rows; the prose rows only under OPT-GUIDE＝提示)
##   strings: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md#7
##     (restore row 生命+40: 0x430710 case 1, RESOURCE 202／203／624／1201)
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")

## Description rows. The original box (0x436d70) has the value rows only; the explanatory prose
## (保留其他狀態, 延長上限, 原始抗性上限…) is the remake's and shows under OPT-GUIDE＝提示.
static func description(item: Dictionary) -> String:
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
	if rows.is_empty(): return description(item)
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
