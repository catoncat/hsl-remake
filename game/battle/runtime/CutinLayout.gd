extends RefCounted
## Where the combat close-up stands its actors: one shared contract for every cut-in path
## (the ordinary strike, the scripted special, the borrowed 氣刃斬 staging and the dedicated
## presenters through BattleCombatCutin._show_shot). The attacker object 0x401c20 (kind 0)
## and the defender object 0x4038a0 both start at viewport + (0x140, 0x14a); the defender then
## remembers that x (+0x8a) and shifts by its ANIMAL row's hit move flag (`k_action`, the
## manifest's `source_k_action`): aniKRight (1) −0x32, aniKLeft (2) +0x1e, aniKStop (0) none.
## On a hit the same flag drives the knock-back — speed 0xe0000 (14 px／tick) decaying 1.0 a
## tick, angle 0 for aniKRight (to the right), 0x80 for aniKLeft (to the left): 14 ticks,
## 105 px; on a miss the dodge slide goes 0x96 (150 px) the same way through 0x45e91e (step
## min(36, distance／4), at least 2, 14 moving ticks and the arrival). The recording shows a
## 拉爾斯帝國兵 (aniKLeft) victim standing at x 350 and ending its knock-back at x 245.
## A side-swapped defender (0x446be0 true: obj_Data9 install, actSetPlayerMode) exchanges its
## aniKRight／aniKLeft at init (0x4044be..0x4044f1) before the shift, so the shift, the
## knock-back and the dodge all run the other way (`swapped`).
## provenance:
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md#4b-普通切入的换边镜像cutin-mirror
##   layout: resource-derived content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT
##   layout: resource-derived content/imported/hsl/global/tables/ANIMAL.H
##   layout: runtime-measured docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##     (recording 2026-09-24: attacker anchor (320,330), aniKLeft victim 350 → 245 after the hit, all on y 330)
##   timing: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md

## The shot line: viewport + (0x140, 0x14a) for both close-up objects (the recording's
## attacker and victim anchors stand on y 330 too).
const SHOT_ANCHOR := Vector2(320, 330)
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
## Hit move flag (ANIMAL.H) → defender x shift at the start of its shot (0x404560).
const K_ACTION_SHIFT := {"aniKStop": 0.0, "aniKRight": -50.0, "aniKLeft": 30.0}
## Hit move flag → direction of the knock-back and the dodge slide (angle 0 = +x, 0x80 = −x).
const K_ACTION_DIRECTION := {"aniKStop": 0.0, "aniKRight": 1.0, "aniKLeft": -1.0}
const KNOCKBACK_SPEED := 14
const DODGE_DISTANCE := 150
const DODGE_MAX_STEP := 36
const DODGE_MIN_STEP := 2


## The actor record's side-swap bit that 0x446be0 reads (+0xa0 & 8): set by the obj_Data9
## install (0x407fc3, the unit's assembled `side_swapped`), flipped by every actSetPlayerMode
## (0x45073c, WinfailActions). Every close-up object of that actor reads it at init and
## mirrors: the attacker object 0x401c20 (ordinary, magic and special kinds), its attack
## flash 0x401310, the defender object 0x4038a0.
static func side_swapped(unit: Dictionary) -> bool:
	return bool(unit.get("side_swapped", false))


## The actor's side word 0x40ba20 (live mode & 0x870000, the magic-only bit kept) is exactly
## pmPlayer: the receiver's hit flash is mirrored then (0x40415b..0x40416a).
static func player_side(unit: Dictionary) -> bool:
	return (ActorRoleRules.side_mask(unit) | (int(unit.get("player_mode", 0)) & ActorRoleRules.MAGIC_ONLY_BIT)) == ActorRoleRules.SIDE_PLAYER


## The defender object's live hit move flag: the row's, aniKRight／aniKLeft exchanged when
## the actor is side-swapped (0x4044be..0x4044f1). A row without one is a data error (the
## combat_animation check requires it) and stands still.
static func k_action(row: Dictionary, swapped: bool = false) -> String:
	var flag := str(row.get("source_k_action", ""))
	if not K_ACTION_SHIFT.has(flag):
		push_error("combat animation row without a known source_k_action: %s" % flag)
		return "aniKStop"
	if swapped:
		return str({"aniKRight": "aniKLeft", "aniKLeft": "aniKRight"}.get(flag, flag))
	return flag


static func attacker_anchor() -> Vector2:
	return SHOT_ANCHOR


## The victim's neutral position in its own shot.
static func defender_anchor(row: Dictionary, swapped: bool = false) -> Vector2:
	return SHOT_ANCHOR + Vector2(K_ACTION_SHIFT[k_action(row, swapped)], 0)


## Knock-back after `ticks` ticks of the hit (the hit tick itself integrates the first step).
static func knockback_x(row: Dictionary, ticks: float, swapped: bool = false) -> float:
	var steps := clampi(int(floor(ticks)) + 1, 0, KNOCKBACK_SPEED) if ticks >= 0.0 else 0
	return K_ACTION_DIRECTION[k_action(row, swapped)] * float(steps * KNOCKBACK_SPEED - steps * (steps - 1) / 2)


## Dodge slide after `ticks` ticks of the miss: 0x45e91e moves min(36, remaining／4) (at
## least 2) a tick and lands when under 2 px remain.
static func dodge_x(row: Dictionary, ticks: float, swapped: bool = false) -> float:
	var direction: float = K_ACTION_DIRECTION[k_action(row, swapped)]
	if ticks < 0.0 or direction == 0.0:
		return 0.0
	var remaining := DODGE_DISTANCE
	for _step in range(int(floor(ticks)) + 1):
		if remaining < DODGE_MIN_STEP:
			remaining = 0
			break
		remaining -= clampi(remaining / 4, DODGE_MIN_STEP, DODGE_MAX_STEP)
	return direction * float(DODGE_DISTANCE - remaining)


## The victim's displacement `ticks` ticks after its hit／miss roll.
static func reaction_x(row: Dictionary, hit: bool, ticks: float, swapped: bool = false) -> float:
	return knockback_x(row, ticks, swapped) if hit else dodge_x(row, ticks, swapped)
