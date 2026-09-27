extends RefCounted
## Actor-side and control ownership for the battle rule model: the control role
## (player_controlled / friendly_ai / enemy_ai) and the original player-mode side bits
## that decide who may target whom and who the win/fail counters count.
## Explicit roles win; fixture/team fallbacks follow.
## provenance:
##   rules: resource-derived content/battles/first_battle.json
##   rules: resource-derived content/imported/hsl/global/tables/TYPE.H
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md
##   rules: user-confirmed (Leonard player-controlled, 023／024 friendly, 021／026 enemy)
##   rules: provisional (fixture／team fallbacks, role-implied side for units without player_mode)

## pmALL: the three side bits of the live +0x28 player mode (pmPlayer 0x10000, pmEnemy
## 0x20000, pmNPC 0x40000). Bit 0x800000 (pmNPCPlayerNoMagic) is not a side and is dropped.
const SIDE_MASK := 0x70000
const SIDE_PLAYER := 0x10000
const SIDE_ENEMY := 0x20000
const SIDE_NPC := 0x40000
## pmMagicAttack's extra bit (0x870000 = pmALL | 0x800000): kept on player_mode, not a side.
const MAGIC_ONLY_BIT := 0x800000
## The side a unit without an installed player_mode has always implied (curated scenarios,
## development fixtures); friendly_ai sits on the player side there.
const ROLE_SIDES := {"player_controlled": SIDE_PLAYER, "friendly_ai": SIDE_PLAYER, "enemy_ai": SIDE_ENEMY}


static func battle_actor_role(unit: Dictionary, role_model: Dictionary = {}) -> String:
	var explicit_role := str(unit.get("battle_actor_role", unit.get("actor_role", "")))
	if explicit_role != "":
		return explicit_role

	var fixture_role := str(unit.get("fixture_role", ""))
	match fixture_role:
		"player_install":
			return "player_controlled"
		"map_object":
			return "map_object"
		"battle_manager":
			return "battle_manager"

	var team := str(unit.get("team", ""))
	match team:
		"player":
			return "player_controlled"
		"ally":
			return "friendly_ai"
		"enemy":
			return "enemy_ai"
	return "unknown"


## Side bits of a unit: the installed `player_mode` (the assembler's 0x407ec0 reading or a
## script actSetPlayerMode) masked to pmALL when the unit carries one, else the side its
## role implies. 0 = no side (map objects, battle manager records, an installed mode
## without side bits): never hostile, never counted, no 0x448840 hp_level term.
static func side_mask(unit: Dictionary, role_model: Dictionary = {}) -> int:
	if unit.has("player_mode"):
		return int(unit["player_mode"]) & SIDE_MASK
	return int(ROLE_SIDES.get(battle_actor_role(unit, role_model), 0))


## Two units are hostile when their side bits share nothing: the AI target scan 0x40bb80
## drops any object with own & other & 0x870000 != 0 and the player's attack range 0x40f8b0
## skips cells whose occupant carries the attacker's side bit. pmPlayerEnemy villagers share
## a bit with both camps and are attacked by neither; pmNPC units fight both.
static func hostile(a: Dictionary, b: Dictionary, role_model: Dictionary = {}) -> bool:
	var side_a := side_mask(a, role_model)
	var side_b := side_mask(b, role_model)
	return side_a != 0 and side_b != 0 and (side_a & side_b) == 0


## Same side for support (heal / buff / item help): the sides overlap. This keeps the
## current contract (friendly_ai helps player_controlled); the original AI support scan
## compares the masks for equality (original_ai_support.md) — provisional boundary.
static func same_side(a: Dictionary, b: Dictionary, role_model: Dictionary = {}) -> bool:
	var side_a := side_mask(a, role_model)
	var side_b := side_mask(b, role_model)
	return side_a != 0 and side_b != 0 and (side_a & side_b) != 0


## The original register / unregister (0x407660 / 0x407720) bumps the enemy total only for
## a side with pmEnemy and without pmPlayer, the player total only for pmPlayer without
## pmEnemy; pmNPC and pmPlayerEnemy units count for neither.
static func counts_as_enemy(unit: Dictionary, role_model: Dictionary = {}) -> bool:
	var side := side_mask(unit, role_model)
	return (side & SIDE_ENEMY) != 0 and (side & SIDE_PLAYER) == 0


static func counts_as_player(unit: Dictionary, role_model: Dictionary = {}) -> bool:
	var side := side_mask(unit, role_model)
	return (side & SIDE_PLAYER) != 0 and (side & SIDE_ENEMY) == 0


## A cell the player's range builder keeps for `target` (0x40f5d0 over 0x40f8b0): a hostile
## occupant, or one whose side is pmALL — an excluded side bit drops the cell only when
## (flags & 0x70000) != 0x70000. The weapon range (0x409090, built with flag 1 by the player
## attack callers 0x43fca5…0x444156) also drops a pmALL occupant carrying 0x800000
## (pmMagicAttack); the magic and special ranges (0x4097d0／0x409830, flag 0) keep it. So the
## level-37 gems take magic and specials only. The AI target scan 0x40bb80 still never picks
## a pmALL unit (own & other & 0x870000 != 0): AI callers keep `hostile`.
static func player_range_selectable(attacker: Dictionary, target: Dictionary, magic_range: bool, role_model: Dictionary = {}) -> bool:
	if hostile(attacker, target, role_model):
		return true
	if side_mask(target, role_model) != SIDE_MASK or str(attacker.get("id", "")) == str(target.get("id", "")):
		return false
	return magic_range or (int(target.get("player_mode", 0)) & MAGIC_ONLY_BIT) == 0
