extends RefCounted
## Source low-HP kernels. Prepared legal actions and all mutations belong to PlayLoop.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_priority.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Decision = preload("res://game/sim/AIDecisionRules.gd")
const Number = preload("res://game/sim/SkillResourceRules.gd")


static func profile_error(profile: Dictionary) -> String:
	for key in ["ai_check_hp", "ai_check_dying"]:
		var value := Number._integer(profile.get(key))
		if value < 0 or value > 100: return "invalid_ai_priority_" + key
	return ""


static func health_error(actor: Dictionary) -> String:
	for key in ["hp", "max_hp"]:
		var value := Number._integer(actor.get(key))
		# This bound keeps all native percentage products inside signed 32-bit.
		if value < 0 or value > 1000000: return "invalid_ai_health_" + key
	return "" if int(actor["max_hp"]) > 0 else "invalid_ai_health_max_hp"


static func choose_check(profile: Dictionary, attempted: int, rng: Variant = null) -> Dictionary:
	var error := profile_error(profile)
	if error != "": return {"ok": false, "reason": error}
	if attempted < 0 or attempted > 3: return {"ok": false, "reason": "invalid_ai_priority_attempts"}
	var draws: Array = []
	var roll := Decision._draw(99, rng, draws) + 1
	var kind := 0
	# 0x440db1..0x440e3d: self recovery (bit2/mode2) precedes dying foes (bit1/mode1).
	for flag in [2, 1]:
		if (attempted & flag) != 0: continue
		attempted |= flag
		if roll <= int(profile["ai_check_hp" if flag == 2 else "ai_check_dying"]):
			kind = flag
			break
		# A failed enabled check draws again, including the last supported check.
		roll = Decision._draw(99, rng, draws) + 1
	return {"ok": true, "kind": kind, "attempted": attempted, "next_roll": roll, "draws": draws}


static func self_recovery(actor: Dictionary, rng: Variant = null) -> Dictionary:
	var error := health_error(actor)
	if error != "": return {"ok": false, "reason": error}
	var draws: Array = []
	var percent := 12 + Decision._draw(18, rng, draws)
	var threshold := int(int(actor["max_hp"]) * percent / 100)
	# 0x40c110 is NOT the enemy scanner's clamp: it retains these remainders.
	if threshold < 10: threshold = 10 + threshold % 10
	elif threshold > 160: threshold = 160 + threshold % 16
	return {"ok": true, "needed": int(actor["max_hp"]) - int(actor["hp"]) >= 10 and int(actor["hp"]) <= threshold,
		"threshold": threshold, "draws": draws}


static func within_square(a: Vector2i, b: Vector2i, radius: int) -> bool:
	return absi(a.x - b.x) <= radius and absi(a.y - b.y) <= radius


static func scan_error(rows: Array, owner_index: int, radius: int, excluded_sid: int) -> String:
	var error := Decision.rows_error(rows, owner_index)
	if error != "": return error
	if radius < 0 or radius > 512: return "invalid_ai_dying_range"
	if excluded_sid < -1 or excluded_sid > 32767: return "invalid_ai_exclusion"
	for row in rows:
		if row == null: continue
		error = health_error(row)
		if error != "": return error
	return ""


static func low_hp_target(rows: Array, owner_index: int, radius: int, excluded_sid: int, cursor: int, rng: Variant = null) -> Dictionary:
	var error := scan_error(rows, owner_index, radius, excluded_sid)
	if error != "": return {"ok": false, "reason": error}
	if cursor < 0 or cursor > 200: return {"ok": false, "reason": "invalid_ai_dying_cursor"}
	var draws: Array = []
	var evaluated: Array = []
	var owner: Dictionary = rows[owner_index]
	for index in range(cursor, rows.size()):
		var row: Variant = rows[index]
		if row == null or index == owner_index or (int(row["side"]) & int(owner["side"]) & 0x870000) != 0: continue
		if not within_square(row["coord"], owner["coord"], radius): continue
		# Original 0x40bf70 does not filter removed/HP0 and checks SID AFTER this draw.
		var percent := 12 + Decision._draw(18, rng, draws)
		var threshold := clampi(int(int(row["max_hp"]) * percent / 100), 10, 80)
		evaluated.append({"index": index, "threshold": threshold})
		var native_sid := -1 if row["removed"] else int(row["sid"])
		if int(row["hp"]) <= threshold and (excluded_sid == -1 or native_sid != excluded_sid):
			return {"ok": true, "index": index, "native_index": index + 1, "draws": draws, "evaluated": evaluated}
	return {"ok": true, "index": -1, "native_index": 0, "draws": draws, "evaluated": evaluated}
