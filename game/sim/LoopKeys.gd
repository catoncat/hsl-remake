extends RefCounted
## Keys of the PlayLoop dictionary that the scene side (BattleSceneRuntime and its
## modules, panels, coordinators, tests/support) reads or mirrors, spelled once.
## BattlePlayLoop and game/sim still write these keys as literals; a key listed
## here is a scene-facing contract, not a new field.
## provenance:
##   rules: remake-invented (dictionary field names of the remake's loop)

const INTERACTION := "interaction"
const SELECTED_UNIT_ID := "selected_unit_id"
const BATTLE_OUTCOME := "battle_outcome"
const UNITS := "units"
const PENDING_MOVE := "pending_move"
const PENDING_MOVE_FROM := "pending_move_from"
const ATTACKED_THIS_ACTION := "attacked_this_action"
const SELECTED_ATTACK := "selected_attack"
const SELECTED_SKILL_ID := "selected_skill_id"
const COMMAND_MENU := "command_menu"
const LAST_ATTACK := "last_attack"
const LAST_ATTACK_REJECT := "last_attack_reject"
const LAST_AI_ACTION := "last_ai_action"
## Read-only presentation input: the battle camera's top-left in map pixels (the original's
## 0x4c091c／0x4c0920). BattleSceneRuntime stamps it before rule operations; rules only read it
## (DropLightningRules) and fall back when it is absent (no scene).
const PRESENTATION_VIEW := "presentation_view"
const LAST_ITEM_USE := "last_item_use"
const LAST_COMBAT := "last_combat"
const KNOWN_UNIT_IDS := "known_unit_ids"
const GIVE_SESSION := "give_session"
const ITEM_REVISION := "item_revision"
const SETTLEMENT := "settlement"
const GOLD := "gold"
const CONSUMABLES := "consumables"
const SKILL_BOOK := "skill_book"
const SKILL_TARGET_DATA := "skill_target_data"
const MAP_SIZE := "map_size"
const TREASURES := "treasures"
const TREASURE_SOURCE := "treasure_source"
const WINFAIL_RUNTIME := "winfail_runtime"
const NEXT_LEVEL_EVENT := "next_level_event"
const NEXT_LEVEL_EVENT_STATUS := "next_level_event_status"
