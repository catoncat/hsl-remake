extends RefCounted
## Condition step of the winfail script interpreter: does a status' leading condition chain
## hold against the PlayLoop dictionary, and which units does a script token (SID_ENEMYnnn,
## SID_PLAYERn, opening bindings) designate right now. Pure reads of the loop; nothing here
## mutates. Rule compilation is WinfailCompiler, result actions WinfailActions, the outcome
## state machine WinfailScenarioRules.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md; static-derived docs/evidence_packets/static_reverse/original_check_targets.md; static-derived docs/evidence_packets/static_reverse/original_round_display.md; provisional (condition polarity, AND prefix — ids in docs/evidence_packets/static_reverse/winfail_claim_limits.md)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const CombatSequence = preload("res://game/sim/CombatSequenceRules.gd")


## ---------------------------------------------------------------------------
## Conditions

static func attacked_ids(battle: Dictionary) -> Array:
	## The remake's attacked list 0x4c29a0 (0x430020 appends every target an attack
	## starts on): the strike's defender and each target of an area skill, not the counter.
	var attack: Dictionary = battle.get("last_attack", {})
	var ids: Array = []
	for hit in [attack] + CombatSequence.participant_outcomes(attack):
		var id := str((hit as Dictionary).get("defender_id", ""))
		if id != "" and not ids.has(id):
			ids.append(id)
	return ids


static func conditions_hold(battle: Dictionary, status: Dictionary, context: String) -> bool:
	var conditions: Array = status.get("conditions", [])
	if conditions.is_empty():
		return false
	for condition_value in conditions:
		var condition: Dictionary = condition_value
		if not bool(condition.get("supported", false)):
			return false
		if not condition_holds(battle, str(condition["name"]), condition["args"], context):
			return false
	return true


static func condition_holds(battle: Dictionary, name: String, args: Array, context: String) -> bool:
	match name:
		"actTRUE":
			return true
		"actCheckRoundNumber":
			return args.size() >= 1 and int(battle.get("turn", 1)) >= int(_arg(args, 0))
		"actCheckRoundDisp":
			return _arg(args, 0).is_valid_int() and int(battle.get("turn", 1)) >= _int_arg(args, 0)
		"actDetectRoundDispDisp":
			if not _arg(args, 0).is_valid_int():
				return false
			var runtime: Dictionary = battle.get("winfail_runtime", {})
			var baseline := int(runtime.get("round_display_baseline", 1))
			return int(battle.get("turn", 1)) >= baseline + _int_arg(args, 0)
		"actCheckEnemyTotalNumber":
			return args.size() >= 1 and _alive_enemy_total(battle) <= int(_arg(args, 0))
		"actCheckEnemyNumber":
			# static-derived (0x450840 case 0x24): holds when the registered count of the
			# code is strictly below num. Static enemy objects drawn without PlayLoop units
			# (Enemy101 hull pieces) stay registered in the original until destroyed; the
			# remake cannot destroy them, so their declared count is added unchanged.
			# An unresolvable token must not satisfy the check through an empty count.
			if args.size() < 2 or token_source(battle, _arg(args, 0)) == "unresolved":
				return false
			var registered := alive_units_for_token(battle, _arg(args, 0)).size() + _static_enemy_count(battle, _arg(args, 0))
			return registered < int(_arg(args, 1))
		"actCheckPlayer", "actCheckEnemy":
			# [num][id1][id2]...: none of the listed ids is still on the field.
			# static-derived: hsl01.exe 0x450840 case 0x23/0x26 counts only ids that
			# lookup_registered_actor_by_code_and_serial (0x44fad0) still finds, so a
			# listed class with no unit at all counts as fallen (WINFAIL533 lists
			# 024/027 that its EVEF never places). A token the remake cannot resolve
			# never counts, so a binding gap cannot decide a battle. A party member the
			# opening binds but this battle never fielded (a conditional install the
			# carry lacks: encounters 5NN during the party split, levels 30-34) is
			# not fallen either — remake rule compensating the carry model: the original
			# fields every registered slot into 5NN (registration is cleared only by
			# actDeletePlayerCode), so a registered-but-absent 雷歐納德 cannot occur there
			# (docs/evidence_packets/static_reverse/original_check_targets.md §R8).
			if args.size() < 2:
				return false
			var needed := mini(int(_arg(args, 0)), args.size() - 1)
			var dead := 0
			for index in range(1, args.size()):
				var token := _arg(args, index)
				var source := token_source(battle, token)
				if source == "unresolved":
					continue
				if source == "binding" and units_for_token(battle, token).is_empty():
					continue
				if alive_units_for_token(battle, token).is_empty():
					dead += 1
			return needed > 0 and dead >= needed
		"actCheckPlayerArriveSysPos":
			if args.size() < 2:
				return false
			var arrival: Dictionary = battle.get("winfail_runtime", {}).get("system_arrival_position", {})
			var position: Array = arrival.get("position", []) if arrival is Dictionary else []
			if position.size() < 2:
				return false
			for unit_id in alive_units_for_token(battle, _arg(args, 0), int(_arg(args, 1))):
				var coord: Variant = unit(battle, unit_id).get("coord", null)
				if coord is Vector2i and coord.x * cell_size(battle) == int(position[0]) and coord.y * cell_size(battle) == int(position[1]):
					return true
			return false
		"actCheckPlayerArrivePos":
			if args.size() < 6:
				return false
			var cells := WinfailCompiler.zone_cells([int(_arg(args, 2)), int(_arg(args, 3)), int(_arg(args, 4)), int(_arg(args, 5))], cell_size(battle))
			for unit_id in alive_units_for_token(battle, _arg(args, 0), int(_arg(args, 1))):
				var coord: Variant = unit(battle, unit_id).get("coord", null)
				if coord is Vector2i:
					for cell_value in cells:
						var cell: Array = cell_value
						if Vector2i(int(cell[0]), int(cell[1])) == coord:
							return true
			return false
		"actCheckPlayerAttacked":
			# static-derived (original_round_display.md «Attack context»): case 0x2a reads the
			# attacker global 0x4c1ce8 (skipped for attacker -1) and the attacked list 0x4c29a0,
			# which only the completion scan of the action that attacked sees ("attack").
			if context != "attack" or args.size() < 2:
				return false
			var attacker := str((battle.get("last_attack", {}) as Dictionary).get("attacker_id", ""))
			if attacker == "" or (_arg(args, 0) != "-1" and not units_for_token(battle, _arg(args, 0)).has(attacker)):
				return false
			var attacked_by := units_for_token(battle, _arg(args, 1))
			return attacked_ids(battle).any(func(id): return attacked_by.has(id))
		"actCheckSerialPlayerAttacked":
			# case 0x6e walks the attacked list only (0x4c1ce8 is not read).
			if context != "attack" or args.size() < 2 or not _arg(args, 1).is_valid_int():
				return false
			var serial_units := units_for_token(battle, _arg(args, 0), _int_arg(args, 1))
			return attacked_ids(battle).any(func(id): return serial_units.has(id))
		"actCheckNotPlayerAttacker":
			# case 0x74 fails only when 0x4c1ce8 is set and names the player: a completion
			# without an attack (0x4c1ce8 cleared at the action's start) satisfies it.
			if args.size() < 1:
				return false
			if context != "attack":
				return true
			var attacker := str((battle.get("last_attack", {}) as Dictionary).get("attacker_id", ""))
			return not units_for_token(battle, _arg(args, 0)).has(attacker)
		"actFALSE":
			return false
		"actCheckPlayerHPLow":
			if args.size() < 3:
				return false
			# static-derived (hsl01.exe 0x450840 case 0x41, 0x452885..0x4528f2): threshold =
			# max HP +0xdc × ratio / 100 (truncating), clamped to at least 1; holds when live HP
			# +0xd8 is not above it. The clamp is what lets `ratio 0` fire on an undead boss,
			# which revives at 1 HP instead of dying (WINFAIL030–041／059／075–079). A defeated
			# unit reads as HP 0 (provisional: the original's lookup no longer finds an
			# unregistered object; the remake keeps the fallen target satisfying the check).
			var ratio := int(_arg(args, 2))
			var serial := _int_arg(args, 1)
			for unit_id in units_for_token(battle, _arg(args, 0), serial):
				var unit := unit(battle, unit_id)
				var hp := int(unit.get("hp", 0))
				if bool(unit.get("defeated", false)):
					hp = 0
				if hp <= hp_low_threshold(int(unit.get("max_hp", 0)), ratio):
					return true
			return false
		"actCheckPlayerTotalNumber":
			return args.size() >= 1 and _alive_player_side_total(battle) <= int(_arg(args, 0))
		"actCheckAnyPlayerArrivePos":
			if args.size() < 4:
				return false
			var any_cells := WinfailCompiler.zone_cells([int(_arg(args, 0)), int(_arg(args, 1)), int(_arg(args, 2)), int(_arg(args, 3))], cell_size(battle))
			for unit_value in battle.get("units", []):
				if typeof(unit_value) != TYPE_DICTIONARY:
					continue
				var unit: Dictionary = unit_value
				if not unit_alive(battle, str(unit.get("id", ""))) or not player_side(unit):
					continue
				var coord: Variant = unit.get("coord", null)
				if coord is Vector2i:
					for cell_value in any_cells:
						var cell: Array = cell_value
						if Vector2i(int(cell[0]), int(cell[1])) == coord:
							return true
			return false
		"actCheckNextSerialNumber":
			# static-derived (original_poison_gas.md, 0x4525e0..0x45260b): a timer on the
			# handoff counter word 0x4c1ad4 (0x407510 bumps it after its scan). A zero deadline
			# word 0x4c1ad6 is armed to counter + num (u16); the condition holds once the
			# counter reaches it and clears the deadline. The only condition that writes: it
			# is read in event scans (_evaluate owns a copy), never by the win／fail readers.
			if not _arg(args, 0).is_valid_int():
				return false
			var runtime: Dictionary = battle.get("winfail_runtime", {})
			var counter := int(runtime.get("handoff_counter", 0)) & 0xffff
			var deadline := int(runtime.get("serial_deadline", 0)) & 0xffff
			if deadline == 0:
				deadline = (_int_arg(args, 0) + counter) & 0xffff
			var holds := deadline <= counter
			runtime["serial_deadline"] = 0 if holds else deadline
			return holds
		"actCheckEventNotExist":
			if args.size() < 2:
				return false
			var statuses: Array = battle.get("event_statuses", [])
			var count := mini(int(_arg(args, 0)), args.size() - 1)
			for index in range(1, 1 + count):
				if statuses.find(int(_arg(args, index))) != -1:
					return false
			return true
		_:
			return false


static func hp_low_threshold(max_hp: int, ratio: int) -> int:
	## actCheckPlayerHPLow's HP threshold (0x450840 case 0x41): max_hp × ratio / 100, at least 1.
	return maxi(1, max_hp * ratio / 100)


static func condition_tokens(status: Dictionary) -> Array:
	var tokens: Array = []
	for condition_value in status.get("conditions", []):
		var condition: Dictionary = condition_value
		var args: Array = condition["args"]
		match str(condition["name"]):
			"actCheckPlayer", "actCheckEnemy":
				for index in range(1, args.size()):
					tokens.append(_arg(args, index))
			"actCheckPlayerArrivePos", "actCheckPlayerHPLow", "actCheckEnemyNumber":
				if args.size() >= 1:
					tokens.append(_arg(args, 0))
	return tokens


## ---------------------------------------------------------------------------
## Token resolution

static func units_for_token(battle: Dictionary, token: String, serial: int = 0) -> Array:
	## Unit ids a script token designates (alive or not). Pure. A serial selects
	## the exact opening binding (SID_ENEMY023,1); a serial-less SID_ENEMYnnn is
	## the whole class (every unit whose class_id/actor_id is that actor, plus
	## any bound unit), as in actCheckEnemyNumber; SID_PLAYERn resolves through
	## its bindings and falls back to player_unit_id; anything else is unresolved.
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	var ids: Array = []
	if token == "":
		return ids
	var bindings: Dictionary = runtime.get("actor_bindings", {})
	var exact := "%s/%d" % [token, serial]
	if serial > 0 and bindings.has(exact) and not unit(battle, str(bindings[exact])).is_empty():
		ids.append(str(bindings[exact]))
		return ids
	if token.begins_with("SID_ENEMY"):
		var digits := token.trim_prefix("SID_ENEMY")
		if digits.is_valid_int():
			var actor_id := "%03d" % int(digits)
			var class_id := "Enemy%s" % actor_id
			for unit_value in battle.get("units", []):
				if typeof(unit_value) != TYPE_DICTIONARY:
					continue
				var unit: Dictionary = unit_value
				if str(unit.get("class_id", "")) == class_id or str(unit.get("actor_id", "")) == actor_id:
					ids.append(str(unit.get("id", "")))
	for key in bindings.keys():
		if str(key).begins_with(token + "/") and not unit(battle, str(bindings[key])).is_empty():
			if ids.find(str(bindings[key])) == -1:
				ids.append(str(bindings[key]))
	if not ids.is_empty() or token.begins_with("SID_ENEMY"):
		return ids
	if token.begins_with("SID_PLAYER"):
		var player_token := str(runtime.get("player_token", ""))
		var player_id := str(battle.get("player_unit_id", ""))
		if player_id != "" and (player_token == "" or player_token == token) and not unit(battle, player_id).is_empty():
			ids.append(player_id)
		return ids
	return ids


static func token_source(battle: Dictionary, token: String) -> String:
	## "binding" | "class" | "player_unit_id_default" | "narration" | "unresolved"
	var runtime: Dictionary = battle.get("winfail_runtime", {})
	if WinfailCompiler.NARRATION_TOKENS.find(token) != -1:
		return "narration"
	for key in (runtime.get("actor_bindings", {}) as Dictionary).keys():
		if str(key).begins_with(token + "/"):
			return "binding"
	if token.begins_with("SID_ENEMY") and token.trim_prefix("SID_ENEMY").is_valid_int():
		return "class"
	if token.begins_with("SID_PLAYER"):
		var player_token := str(runtime.get("player_token", ""))
		if str(battle.get("player_unit_id", "")) != "" and (player_token == "" or player_token == token):
			return "player_unit_id_default"
	return "unresolved"


static func alive_units_for_token(battle: Dictionary, token: String, serial: int = 0) -> Array:
	var alive: Array = []
	for unit_id in units_for_token(battle, token, serial):
		if unit_alive(battle, str(unit_id)):
			alive.append(str(unit_id))
	return alive


static func _static_enemy_count(battle: Dictionary, token: String) -> int:
	## Static enemy objects the scenario declares for a token (map objects drawn
	## without units). They are never destroyed in the remake (provisional boundary).
	var counts: Dictionary = (battle.get("winfail_runtime", {}) as Dictionary).get("static_enemy_counts", {})
	return int(counts.get(token, 0))


static func unit_alive(battle: Dictionary, unit_id: String) -> bool:
	var unit := unit(battle, unit_id)
	if unit.is_empty() or bool(unit.get("defeated", false)) or int(unit.get("hp", 1)) <= 0:
		return false
	var departed: Array = (battle.get("winfail_runtime", {}) as Dictionary).get("departed_unit_ids", [])
	return departed.find(unit_id) == -1


static func _alive_enemy_total(battle: Dictionary) -> int:
	var count := 0
	for unit_value in battle.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if not unit_alive(battle, str(unit.get("id", ""))):
			continue
		var role := ActorRoleRules.battle_actor_role(unit)
		# 0x4c1b94 counts sides with pmEnemy and without pmPlayer (0x407660 / 0x407720);
		# pmNPC third parties and pmPlayerEnemy villagers are not enemies here.
		# provisional: units without an explicit role count as enemies by class prefix.
		if ActorRoleRules.counts_as_enemy(unit) or (role == "unknown" and str(unit.get("class_id", "")).begins_with("Enemy")):
			count += 1
	return count


static func _alive_player_side_total(battle: Dictionary) -> int:
	var count := 0
	for unit_value in battle.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		# 0x4c1b90 counts sides with pmPlayer and without pmEnemy (0x407660 / 0x407720).
		if unit_alive(battle, str(unit.get("id", ""))) and (ActorRoleRules.counts_as_player(unit) or (ActorRoleRules.battle_actor_role(unit) == "unknown" and bool(unit.get("player_commandable", false)))):
			count += 1
	return count


static func player_side(unit: Dictionary) -> bool:
	var role := ActorRoleRules.battle_actor_role(unit)
	return role == "player_controlled" or role == "friendly_ai" or (role == "unknown" and bool(unit.get("player_commandable", false)))


static func unit(battle: Dictionary, unit_id: String) -> Dictionary:
	if unit_id == "":
		return {}
	for unit_value in battle.get("units", []):
		if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("id", "")) == unit_id:
			return unit_value
	return {}


static func cell_size(battle: Dictionary) -> int:
	return int((battle.get("winfail_script_rules", {}) as Dictionary).get("cell_size", WinfailCompiler.DEFAULT_CELL_SIZE))


## ---------------------------------------------------------------------------
## Helpers

static func _arg(args: Array, index: int, default: String = "") -> String:
	return WinfailCompiler.arg(args, index, default)


static func _int_arg(args: Array, index: int, default: int = 0) -> int:
	return WinfailCompiler.int_arg(args, index, default)
