extends SceneTree
## Bounded rules audit, not a difficulty guarantee or rendered input test.
## Default roster/attributes; seeds 10..29; no HP/damage/EXP overrides.
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://ignored/first-battle-balance")
	var results: Array = []
	for policy in ["retreat", "reckless", "heal_then_advance"]:
		for trial in range(20):
			var rng := RandomNumberGenerator.new()
			rng.seed = trial + 10
			var battle := BattlePlayLoop.begin_battle(BattleFixture.loop())
			var steps := 0
			var healing := 0
			while not BattleOutcome.decided(battle) and steps < 500:
				steps += 1
				if BattleOutcome.decided(battle):
					break
				if battle["interaction"] == "ai_resolving":
					battle = BattlePlayLoop.step_ai_turn(battle, rng)
					continue
				var player := BattlePlayLoop.unit(battle, "leonard")
				if int(player["pending_stat_points"]) > 0:
					var count := int(player["pending_stat_points"]) / 3
					battle = BattlePlayLoop.allocate_growth(battle, "leonard", {"health": count, "attack": count, "defense": count})
					player = BattlePlayLoop.unit(battle, "leonard")
				if policy != "reckless" and int(player["hp"]) <= int(player["max_hp"]) / 2 and player["inventory"].has(241):
					battle = BattlePlayLoop.use_item(battle, "241")
					healing += 1
					continue
				if battle["objective_phase"] == "escape" and policy != "reckless":
					var mover := player.duplicate(true)
					var gate: Vector2i = battle["escape_zone"][0]
					var reach := BattlePlayLoop.TacticalGridRules.movement_reachability_envelope(mover, battle["units"], battle["tiles"], battle["map_size"], 1000)
					var path: Array = reach["reachable_by_coord"].get(gate, {}).get("path", [])
					var cells := BattlePlayLoop.movement_cells(battle, "leonard")
					for index in range(path.size() - 1, -1, -1):
						if cells.has(path[index]):
							battle = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(battle, "move"), path[index])
							break
				elif policy != "retreat":
					# Existing nearest/reachable ordinary AI as an explicit simple player
					# policy; no injected health/damage and no assertion of optimal tactics.
					battle = BattleLoopAI._ai_take_turn(battle, "leonard", rng)["loop"]
				battle = BattlePlayLoop.begin_wait_resolution(battle)
			var player := BattlePlayLoop.unit(battle, "leonard")
			var result := {"policy": policy, "seed": trial + 10, "outcome": battle["battle_outcome"], "turn": battle["turn"], "hp": player["hp"], "level": player["level"], "potions_used": healing, "steps": steps}
			results.append(result)
			print(JSON.stringify(result))
	FileAccess.open("res://ignored/first-battle-balance/receipt.json", FileAccess.WRITE).store_string(JSON.stringify(results, "  "))
	print("BOUNDED_BALANCE_AUDIT_DONE trials=60")
	quit()
