extends RefCounted
## Call distribution and adoption only. PlayLoop owns and commits pending IDs.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_calls.md
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")


static func recipients(rows: Array, owner_index: int, radius: int) -> Dictionary:
	var error := AIDecisionRules.rows_error(rows, owner_index)
	if error != "": return {"ok": false, "reason": error}
	if radius < 0 or radius > 512: return {"ok": false, "reason": "invalid_ai_call_range"}
	var owner: Dictionary = rows[owner_index]
	var indices: Array = []
	for index in range(rows.size()):
		var row: Variant = rows[index]
		if row == null or index == owner_index: continue
		# Unlike target search, native broadcast uses exact masked equality and
		# does not inspect the removed bit. Live unavailable slots are null inputs.
		if (int(row["side"]) & 0x870000) == (int(owner["side"]) & 0x870000) and AIDecisionRules._squared_distance(row["coord"], owner["coord"]) <= radius * radius:
			indices.append(index)
	return {"ok": true, "indices": indices, "source": "0x40bee0"}


static func adopt(ordinary_index: int, pending_index: int, pending_present: bool, pending_eligible: bool) -> Dictionary:
	# The caller consumes a pending call only when ordinary search found nothing.
	# Eligibility is checked against current identity/life/exclusion before commit.
	var consumed := ordinary_index < 0 and pending_present
	return {"index": pending_index if consumed and pending_eligible else ordinary_index,
		"consumed": consumed, "used": consumed and pending_eligible,
		"broadcast": ordinary_index >= 0,
		"source": "0x43f6c2..0x43f74e"}
