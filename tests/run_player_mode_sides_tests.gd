extends "res://tests/support/TestSuite.gd"

## Side bits of the installed player mode (docs/evidence_packets/static_reverse/
## original_player_mode_sides.md): who may target whom, who the win/fail counters count,
## and the level-6 / level-531 all-wait rounds the packet's comparison table quotes.
## Prints one `PLAYER_MODE_SIDES_ATTACK level=… round=… attacker=… defender=…` line per AI
## exchange so the remake column of the table is reproducible from this suite.

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const Roles = preload("res://game/sim/ActorRoleRules.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const PM_PLAYER := 0x10000
const PM_ENEMY := 0x20000
const PM_PLAYER_ENEMY := 0x30000
const PM_NPC := 0x40000
const PM_NPC_PLAYER := 0x50000


func _init() -> void:
	tag = "PLAYER_MODE_SIDES_TESTS"


func run() -> void:
	_test_side_mask_reads_player_mode_then_role()
	_test_hostility_matrix_follows_disjoint_side_bits()
	_test_counters_follow_register_side_rule()
	_test_player_attack_gate_and_skill_side()
	_test_set_player_mode_writes_mode_and_role()
	_test_pm_all_occupant_ranges()
	_test_level6_soldiers_never_attack_villagers()
	_test_level531_npc_rider_is_hostile_to_both_camps()


func _unit(role: String, mode: Variant = null, id: String = "u") -> Dictionary:
	var unit := {"id": id, "battle_actor_role": role, "hp": 10}
	if mode != null:
		unit["player_mode"] = mode
	return unit


func _test_side_mask_reads_player_mode_then_role() -> void:
	check(Roles.side_mask(_unit("player_controlled")) == PM_PLAYER, "player_controlled without player_mode is pmPlayer")
	check(Roles.side_mask(_unit("friendly_ai")) == PM_PLAYER, "friendly_ai without player_mode keeps the player side it always implied")
	check(Roles.side_mask(_unit("enemy_ai")) == PM_ENEMY, "enemy_ai without player_mode is pmEnemy")
	check(Roles.side_mask(_unit("friendly_ai", PM_PLAYER_ENEMY)) == PM_PLAYER_ENEMY, "installed pmPlayerEnemy wins over the role")
	check(Roles.side_mask(_unit("enemy_ai", PM_NPC)) == PM_NPC, "installed pmNPC wins over the role")
	check(Roles.side_mask(_unit("friendly_ai", 0x850000)) == PM_NPC_PLAYER, "pmNPCPlayerNoMagic masks to its pmALL side bits")
	check(Roles.side_mask({"id": "tree", "fixture_role": "map_object"}) == 0, "a map object has no side")


func _test_hostility_matrix_follows_disjoint_side_bits() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	var enemy := _unit("enemy_ai", PM_ENEMY, "e")
	var npc := _unit("enemy_ai", PM_NPC, "n")
	var villager := _unit("friendly_ai", PM_PLAYER_ENEMY, "v")
	var ally := _unit("friendly_ai", PM_NPC_PLAYER, "a")
	# 0x40bb80: own & other & 0x870000 != 0 excludes the candidate.
	check(Roles.hostile(player, enemy) and Roles.hostile(enemy, player), "pmPlayer and pmEnemy are mutual targets")
	check(Roles.hostile(player, npc) and Roles.hostile(npc, player), "pmNPC and pmPlayer are mutual targets")
	check(Roles.hostile(enemy, npc) and Roles.hostile(npc, enemy), "pmNPC and pmEnemy are mutual targets (three-way battle)")
	check(not Roles.hostile(enemy, villager) and not Roles.hostile(villager, enemy), "pmPlayerEnemy shares pmEnemy: the enemy AI never selects a villager")
	check(not Roles.hostile(player, villager) and not Roles.hostile(villager, player), "pmPlayerEnemy shares pmPlayer: the player cannot target a villager")
	check(Roles.hostile(villager, npc), "a pmPlayerEnemy villager is hostile only to pmNPC")
	check(not Roles.hostile(ally, player) and Roles.hostile(ally, enemy) and not Roles.hostile(ally, npc), "pmNPCPlayer sides with the player, fights pmEnemy, shares pmNPC")
	check(not Roles.hostile(player, {"id": "tree", "fixture_role": "map_object"}), "no side is never hostile")
	check(Roles.same_side(player, ally) and Roles.same_side(villager, player) and Roles.same_side(villager, enemy), "support same-side is an overlapping side")
	check(not Roles.same_side(npc, player) and not Roles.same_side(enemy, player), "disjoint sides are not the same side")
	# Units without player_mode keep the pre-R22 contract.
	check(Roles.hostile(_unit("player_controlled"), _unit("enemy_ai")) and not Roles.hostile(_unit("player_controlled"), _unit("friendly_ai")), "role-only units: player vs enemy hostile, player vs friendly not")


func _test_counters_follow_register_side_rule() -> void:
	# 0x407660 / 0x407720: enemy total counts pmEnemy without pmPlayer, player total pmPlayer without pmEnemy.
	check(Roles.counts_as_enemy(_unit("enemy_ai", PM_ENEMY)) and Roles.counts_as_enemy(_unit("enemy_ai", 0x60000)), "pmEnemy and pmNPCEnemy count as enemies")
	check(not Roles.counts_as_enemy(_unit("enemy_ai", PM_NPC)), "pmNPC does not count as an enemy")
	check(not Roles.counts_as_enemy(_unit("friendly_ai", PM_PLAYER_ENEMY)) and not Roles.counts_as_player(_unit("friendly_ai", PM_PLAYER_ENEMY)), "pmPlayerEnemy counts for neither side")
	check(Roles.counts_as_player(_unit("player_controlled", PM_PLAYER)) and Roles.counts_as_player(_unit("friendly_ai", PM_NPC_PLAYER)), "pmPlayer and pmNPCPlayer count as players")
	check(Roles.counts_as_enemy(_unit("enemy_ai")) and Roles.counts_as_player(_unit("friendly_ai")), "role-only units count by their implied side")
	var battle := {"units": [
		_unit("player_controlled", PM_PLAYER, "p"), _unit("enemy_ai", PM_ENEMY, "e1"), _unit("enemy_ai", PM_ENEMY, "e2"),
		_unit("enemy_ai", PM_NPC, "n"), _unit("friendly_ai", PM_PLAYER_ENEMY, "v"),
	]}
	check(WinfailConditions._alive_enemy_total(battle) == 2, "actCheckEnemyTotalNumber counts the two pmEnemy units, not the pmNPC rider or the villager")
	check(WinfailConditions._alive_player_side_total(battle) == 1, "actCheckPlayerTotalNumber counts the pmPlayer unit only")


func _test_player_attack_gate_and_skill_side() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	check(Roles.can_player_attack_actor(player, _unit("enemy_ai", PM_NPC, "n")), "the player may attack a pmNPC unit")
	check(not Roles.can_player_attack_actor(player, _unit("friendly_ai", PM_PLAYER_ENEMY, "v")), "the player may not attack a pmPlayerEnemy villager (0x40f8b0 mode 2 skips pmPlayer cells)")
	var dead := _unit("enemy_ai", PM_ENEMY, "d")
	dead["hp"] = 0
	check(not Roles.can_player_attack_actor(player, dead), "a fallen unit is no target")
	var skill_data := {"skills": {}}
	var offensive := {"function_bits": 0, "range": "range1Cell", "effect_range": "range0Cell"}
	check(Loop.SkillTargetRules.side_matches(player, _unit("enemy_ai", PM_NPC, "n"), offensive, skill_data), "an offensive skill reaches a pmNPC unit")
	check(not Loop.SkillTargetRules.side_matches(player, _unit("friendly_ai", PM_PLAYER_ENEMY, "v"), offensive, skill_data), "an offensive skill does not reach a villager")


## 0x40f5d0 keeps a pmALL occupant in every player range except the weapon range (0x409090,
## flag 1), which drops pmMagicAttack's 0x800000; the AI keeps disjoint sides (0x40bb80).
## The level-37 gems: magic／specials only; an undeclared gem with nothing to target waits.
func _test_pm_all_occupant_ranges() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	var gem := _unit("friendly_ai", 0x870000, "gem")
	var door := _unit("friendly_ai", 0x70000, "door")
	var villager := _unit("friendly_ai", PM_PLAYER_ENEMY, "v")
	var enemy := _unit("enemy_ai", PM_ENEMY, "e")
	check(not Roles.player_range_selectable(player, gem, false) and Roles.player_range_selectable(player, gem, true), "a pmMagicAttack gem is out of the weapon range, inside the magic／special range")
	check(Roles.player_range_selectable(player, door, false) and Roles.player_range_selectable(player, door, true), "a plain pmALL occupant stays in every player range")
	check(not Roles.player_range_selectable(player, villager, false) and not Roles.player_range_selectable(player, villager, true), "a pmPlayerEnemy occupant (a gem switched off) stays out of both")
	check(Roles.player_range_selectable(player, enemy, false) and not Roles.player_range_selectable(gem, gem, true), "hostile units stay selectable; nobody selects itself")
	var skill_data := {"skills": {}}
	var offensive := {"function_bits": 0, "range": "range1Cell", "effect_range": "range0Cell"}
	check(Loop.SkillTargetRules.side_matches(player, gem, offensive, skill_data), "a player offensive skill reaches a gem")
	check(not Loop.SkillTargetRules.side_matches(enemy, gem, offensive, skill_data), "an AI caster never targets a pmALL gem (0x40bb80)")
	# 0x40fdc0 (the area mask 0x4104d0 walks): a pmALL occupant is kept whatever the caster's
	# excluded side, so an AI's offensive area around its target takes a gem in too (R6-L11).
	check(Loop.SkillTargetRules.area_side_matches(enemy, gem, offensive, skill_data) and Loop.SkillTargetRules.area_side_matches(player, gem, offensive, skill_data), "every caster's offensive area takes in a pmALL gem")
	check(not Loop.SkillTargetRules.area_side_matches(enemy, villager, offensive, skill_data) and not Loop.SkillTargetRules.area_side_matches(gem, gem, offensive, skill_data), "the area keeps excluding the caster's own side (a switched-off gem is pmPlayerEnemy) and the caster itself")
	var profiles := {"actors": {"067": {"missing_required": ["find_type", "find_range", "ai_call_range", "ai_fixed"]}}}
	gem["actor_id"] = "067"
	var board := {"ai_profiles": profiles, "units": [gem, player, enemy]}
	check(Loop.AI._idle_without_strategy(board, gem), "an undeclared gem with no hostile unit waits")
	var npc := _unit("enemy_ai", PM_NPC, "n")
	gem["player_mode"] = PM_PLAYER_ENEMY
	board["units"].append(npc)
	check(not Loop.AI._idle_without_strategy(board, gem), "a switched-off gem facing a pmNPC unit is not idle: the missing strategy still fails")
	profiles["actors"]["067"]["missing_required"] = []
	check(not Loop.AI._idle_without_strategy({"ai_profiles": profiles, "units": [gem, player]}, gem), "a declared strategy takes the ordinary AI turn")


func _test_set_player_mode_writes_mode_and_role() -> void:
	var next := {"units": [{"id": "claudie", "actor_id": "009", "battle_actor_role": "enemy_ai", "player_commandable": false, "player_mode": PM_ENEMY, "hp": 30}],
		"winfail_runtime": {"actor_bindings": {"SID_克羅蒂/1": "claudie"}}}
	var runtime := {"mode_changes": [], "unsupported_encountered": []}
	WinfailActions._apply_player_mode(next, runtime, "event_6", ["SID_克羅蒂", "1", "pmPlayerEnemy", "0"])
	var unit: Dictionary = next["units"][0]
	check(runtime["mode_changes"].size() == 1 and runtime["mode_changes"][0]["unit_ids"] == ["claudie"], "the bound token resolves to the unit")
	check(unit["battle_actor_role"] == "friendly_ai" and unit["player_mode"] == PM_PLAYER_ENEMY and not unit["player_commandable"], "WINFAIL036 event 6 pmPlayerEnemy: AI-driven, side pmPlayerEnemy")
	check(runtime["unsupported_encountered"].is_empty(), "pmPlayerEnemy is a supported mode")
	WinfailActions._apply_player_mode(next, runtime, "event_7", ["SID_克羅蒂", "1", "pmPlayer", "1"])
	check(unit["battle_actor_role"] == "player_controlled" and unit["player_mode"] == PM_PLAYER and unit["player_commandable"], "pmPlayer returns control and the pmPlayer side")
	# R6-L10: WINFAIL037 swaps the level-37 gems between pmPlayerEnemy and pmMagicAttack; the
	# pmALL side is now read by ActorRoleRules.player_range_selectable (0x40f5d0 callers).
	WinfailActions._apply_player_mode(next, runtime, "event_x", ["SID_克羅蒂", "1", "pmMagicAttack", "0"])
	check(runtime["unsupported_encountered"].is_empty() and unit["player_mode"] == 0x870000 and unit["battle_actor_role"] == "friendly_ai" and not unit["player_commandable"], "pmMagicAttack is a supported mode: AI-driven, side pmALL plus 0x800000")
	check(WinfailActions.PLAYER_MODE_ROLES[PM_NPC] == "enemy_ai", "pmNPC maps to enemy_ai")


func _reach_player(loop: Dictionary, label: String, attacks: Array, level: int, rng: RandomNumberGenerator) -> Dictionary:
	## Every AI unit takes its ordinary step_ai_turn (as the autoplay sweep does) until the
	## next controlled action menu; each settled exchange is recorded and printed.
	var next := loop
	for _step in range(4096):
		if str(next.get("interaction", "")) == "action_menu" or BattleOutcome.decided(next):
			return next
		if Loop.loot_waiting(next):
			var settlement: Dictionary = next["settlement"]
			next = Loop.finish_rewards(next, int(settlement["sequence"]), int(settlement["revision"]), false, true)
			continue
		if str(next.get("interaction", "")) != "ai_resolving":
			_assert_true(false, "%s stops in %s (%s)" % [label, str(next.get("interaction", "")), str(next.get("scenario_error", ""))])
			return next
		var before := int(next.get("last_combat", {}).get("sequence", 0))
		var stepped := Loop.step_ai_turn(next, rng)
		if stepped == next:
			_assert_true(false, "%s: step_ai_turn made no progress" % label)
			return next
		next = stepped
		var combat: Dictionary = next.get("last_combat", {})
		# A caster buffing itself (0x43fce1..0x43fd46: no ally in need, own mask useful) is a support cast, not an exchange.
		if int(combat.get("sequence", 0)) > before and str(combat.get("attacker_id", "")) != str(combat.get("defender_id", "")):
			var attacker := Loop._unit(next, str(combat.get("attacker_id", "")))
			var defender := Loop._unit(next, str(combat.get("defender_id", "")))
			attacks.append({"attacker": attacker, "defender": defender, "round": int(next.get("turn", 0))})
			print("PLAYER_MODE_SIDES_ATTACK level=%d round=%d attacker=%s(%s,0x%x) defender=%s(%s,0x%x)" % [level, int(next.get("turn", 0)),
				str(attacker.get("id", "")), str(attacker.get("actor_id", "")), Roles.side_mask(attacker),
				str(defender.get("id", "")), str(defender.get("actor_id", "")), Roles.side_mask(defender)])
	_assert_true(false, "%s did not return to a player action" % label)
	return next


func _all_wait_rounds(level: int, rounds: int, attacks: Array) -> Dictionary:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_%03d.json" % level)
	var loop := Loop.create([], "", scenario, level)
	_assert_true(bool(loop.get("scenario_ok", false)), "level %d PlayLoop creates (%s)" % [level, str(loop.get("scenario_error", ""))])
	if not bool(loop.get("scenario_ok", false)):
		return loop
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	loop = Loop.begin_battle(loop)
	loop = _reach_player(loop, "level %d battle start" % level, attacks, level, rng)
	var guard := 0
	while int(loop.get("turn", 0)) < rounds and guard < 64 and not BattleOutcome.decided(loop):
		if str(loop.get("interaction", "")) != "action_menu":
			print("PLAYER_MODE_SIDES_STOP level=%d turn=%d interaction=%s error=%s" % [level, int(loop.get("turn", 0)), str(loop.get("interaction", "")), str(loop.get("scenario_error", ""))])
			break
		loop = Loop.choose_command(loop, "wait")
		loop = _reach_player(loop, "level %d round %d" % [level, rounds], attacks, level, rng)
		guard += 1
	return loop


func _test_level6_soldiers_never_attack_villagers() -> void:
	var attacks: Array = []
	var loop := _all_wait_rounds(6, 3, attacks)
	if not bool(loop.get("scenario_ok", false)):
		return
	var villagers: Array = loop["units"].filter(func(unit): return str(unit.get("actor_id", "")) in ["061", "062"])
	check(villagers.size() == 12 and villagers.all(func(unit): return int(unit.get("player_mode", 0)) == PM_PLAYER_ENEMY and str(unit["battle_actor_role"]) == "friendly_ai"), "level 6 fields twelve pmPlayerEnemy villagers as uncommandable AI")
	var captain := Loop.unit(loop, "guard024_1")
	# 0x448840 drops the hp_level term for a live pmEnemy side (JobStatsRules.base_values):
	# the swapped 024 is 42 at L1, not the pmPlayer template's 43, before the +30 word.
	check(int(captain.get("max_hp", 0)) == 72 and int(captain.get("object_hit_point", 0)) == 30, "the inserted captain carries the +30 obj_HitPoint word (42 -> 72)")
	check(int(loop.get("turn", 0)) >= 2, "level 6 all-wait reaches round 2 (turn=%d)" % int(loop.get("turn", 0)))
	for record in attacks:
		var attacker: Dictionary = record["attacker"]
		var defender: Dictionary = record["defender"]
		check(Roles.hostile(attacker, defender), "every exchange is between disjoint sides: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
		check(not (str(defender.get("actor_id", "")) in ["061", "062"]), "no soldier attacks a villager: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
		check(not (str(attacker.get("actor_id", "")) in ["061", "062"]), "no villager attacks anyone: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
	check(attacks.size() > 0, "the soldiers do engage the party in the first two rounds")
	print("PLAYER_MODE_SIDES_LEVEL6 rounds=%d exchanges=%d villagers_attacked=0 outcome=%s" % [int(loop.get("turn", 0)), attacks.size(), BattleOutcome.of(loop)])


func _test_level531_npc_rider_is_hostile_to_both_camps() -> void:
	var attacks: Array = []
	var loop := _all_wait_rounds(531, 3, attacks)
	if not bool(loop.get("scenario_ok", false)):
		return
	var rider := Loop.unit(loop, "actor049_1")
	check(not rider.is_empty() and int(rider.get("player_mode", 0)) == PM_NPC and str(rider.get("battle_actor_role", "")) == "enemy_ai", "encounter 531 fields the pmNPC 049 rider as AI")
	var captain := Loop.unit(loop, "actor024_1")
	check(int(captain.get("player_mode", 0)) == PM_ENEMY and int(captain.get("object_hit_point", 0)) == 50 and int(captain.get("max_hp", 0)) == 92, "the swapped 024 captain carries +50 HP (42 -> 92; no hp_level term on the pmEnemy side)")
	check(Roles.hostile(rider, captain) and Roles.hostile(rider, Loop.unit(loop, "leonard")), "the pmNPC rider is hostile to the pmEnemy captain and to the party")
	check(not Roles.counts_as_enemy(rider), "the rider does not count for actCheckEnemyTotalNumber")
	var three_way := 0
	for record in attacks:
		check(Roles.hostile(record["attacker"], record["defender"]), "every 531 exchange is between disjoint sides")
		if str(record["attacker"].get("actor_id", "")) == "049" or str(record["defender"].get("actor_id", "")) == "049":
			three_way += 1
	check(three_way > 0, "the pmNPC rider and the pmEnemy escort exchange blows (three-way battle)")
	print("PLAYER_MODE_SIDES_LEVEL531 rounds=%d exchanges=%d rider_exchanges=%d outcome=%s" % [int(loop.get("turn", 0)), attacks.size(), three_way, BattleOutcome.of(loop)])
