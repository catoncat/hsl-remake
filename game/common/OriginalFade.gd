extends RefCounted
## The original's fade to black 0x42dc90(2) → 0x46098f: level 1 at once, one level more every
## LEVEL_TICKS (0x460a58), black (16) after 30 ticks, done at DONE_TICKS. The title's exits
## (TitleScreen) and the 回憶錄 list's load (BattleSystemMenu) both run it.
## provenance:
##   timing: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (fade 0x42dc90(2), 0x46098f／0x460a58)

const OriginalTick = preload("res://game/common/OriginalTick.gd")

const LEVELS := 16
const LEVEL_TICKS := 2
const DONE_TICKS := 32
const TO_BLACK_SECONDS := DONE_TICKS * OriginalTick.TICK_SECONDS


## Black overlay alpha `elapsed` seconds into the fade.
static func alpha(elapsed: float) -> float:
	var ticks := int(elapsed / OriginalTick.TICK_SECONDS)
	return float(mini(LEVELS, 1 + ticks / LEVEL_TICKS)) / LEVELS
