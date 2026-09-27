extends RefCounted
## obj_Data7 bit 31 (level 12／26 hull pieces 101, 0x80000065): the first such object of the
## level builds the live record (0x44cb10) and every later one takes the same record index
## (+0xa4, 0x42bdb0..0x42be0b), so the pieces are one 0x1fc-byte record — one HP pool. The
## remake keeps one unit per piece and folds the HP each settled action wrote back into a
## pool shared by every living piece of the group (units carrying the same `shared_record`).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md
##   rules: provisional
##     (only HP is pooled — status, side word and stats stay per unit; a piece left at 0 stays down, the others keep the
##     last positive pool)
const Presence = preload("res://game/sim/BattlePresenceRules.gd")


## Called once per settled action (BattleLoopScript.resolve_outcome): every piece started
## the action at the pool, so the pool moves by the sum of the pieces' changes.
static func sync(loop: Dictionary) -> void:
	var groups: Dictionary = {}
	for unit in loop.get("units", []):
		if unit is Dictionary and str(unit.get("shared_record", "")) != "":
			var key := str(unit["shared_record"])
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(unit)
	if groups.is_empty():
		return
	var pools: Dictionary = loop.get("shared_record_hp", {})
	for key in groups.keys():
		var members: Array = groups[key]
		var state: Dictionary = pools.get(key, {"hp": int((members[0] as Dictionary).get("hp", 0)), "down": []})
		var pool := int(state["hp"])
		var down: Array = state["down"]
		var total := pool
		for unit in members:
			var unit_id := str(unit.get("id", ""))
			if Presence.living(unit):
				total += int(unit.get("hp", 0)) - pool
			elif not down.has(unit_id):
				# Downed during this action: its last blow still came off the pool.
				down.append(unit_id)
				total += int(unit.get("hp", 0)) - pool
		total = mini(total, int((members[0] as Dictionary).get("max_hp", total)))
		if total > 0:
			for unit in members:
				if Presence.living(unit):
					unit["hp"] = total
			state["hp"] = total
		pools[key] = state
	loop["shared_record_hp"] = pools
