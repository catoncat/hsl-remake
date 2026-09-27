extends RefCounted
## The PlayLoop `interaction` states, spelled once. The loop dictionary's `interaction`
## key (LoopKeys.INTERACTION) takes one of the ten battle states; the scene runtime's
## `interaction_state` mirrors it and adds OPENING_TIMELINE while the opening coordinator
## owns the frame. NO_CELL is the one "no grid cell" sentinel on the scene side (hover
## off-map, unit without a mirrored cell); (0,0) is a legal cell and never means "none".
## provenance:
##   rules: remake-invented (state vocabulary of the remake's turn loop; the original's mode words are not recovered)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const IDLE := "idle"
const ACTION_MENU := "action_menu"
const MOVE_SELECT := "move_select"
const ATTACK_SELECT := "attack_select"
const MAGIC_SELECT := "magic_select"
const SPECIAL_SELECT := "special_select"
const GIVE_SESSION := "give_session"
const AI_RESOLVING := "ai_resolving"
const BATTLE_RESULT := "battle_result"
const SCENARIO_ERROR := "scenario_error"
## Scene-only: the opening coordinator holds the frame; the loop itself is still IDLE.
const OPENING_TIMELINE := "opening_timeline"

## States in which the player is choosing a target cell on the field.
const TARGETING := [MOVE_SELECT, ATTACK_SELECT]
## States in which the selected unit is under player control on the field.
const PLAYER_CONTROL := [ACTION_MENU, MOVE_SELECT, ATTACK_SELECT]

const NO_CELL := Vector2i(-1, -1)
