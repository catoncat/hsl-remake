"""Compile and validate scene opening timelines (opening_timeline_compile:N, opening_timeline_check:N).

Compile: an original STORY action order becomes a scene opening timeline manifest. Inputs are
either an imported chapter script IR (`hsl_chapter01_script_ir.v1`, flat `action_chain`) or
a tracked battle seed (`hsl_battle_seed.v1`, nested `scripts.story.sections[].actions[].chain[]`).
Both preserve the original action order and arguments; the compiler only re-labels tokens
into presentation kinds and appends one explicit synthetic first-control handoff marker.

Check: a compiled manifest is validated against its source-script profile (PROFILES: first /
last kind, required kinds and message ids per STORY script).

Registry tasks (tools/hsl.py check ...; legacy entries tools/hsl_opening_timeline_compile.py and
tools/hsl_opening_timeline_check.py): opening_timeline_compile:N recompiles the level's seed
and compares the tracked manifest byte for byte (opening_timeline_compile:chapter01: the
chapter-wide manifest from the story051 script IR that the development trials load);
opening_timeline_check:N is the pure profile checker (no regeneration path).
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from hsltools.legacy import imported_levels
from hsltools.levels import CHAPTER_SHARED, encode_json, legacy_failures
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask, NoRegenerationPath, Task


SCHEMA = "hsl_first_scene_opening_timeline.v1"
DEFAULT_STORY = Path("content/imported/hsl/chapter01/scripts/story051.json")
DEFAULT_OUTPUT = Path("content/imported/hsl/chapter01/opening_timeline.json")
SEED_SCHEMA = "hsl_battle_seed.v1"

# The original level music table 0x477b44 (int16 per level 0-99) behind the level-track
# resolver 0x42c1c0; a level >= 100 (501-578, 900-904, 998, 999) resolves to -1, which
# PlayMusic 0x42c250 reads as "keep the current track". static-derived:
# docs/evidence_packets/static_reverse/original_music.md §1-§2. This is the only copy of the
# table: timeline events and scene files carry the resolved track, the runtime looks nothing up.
LEVEL_MUSIC_TABLE: tuple[int, ...] = (
    3, 13, 12, 14, 2, 18, 17, 13, 11, 16,
    15, 2, 14, 15, 2, 12, 2, 12, 18, 17,
    2, 14, 17, 2, 19, 2, 12, 2, 13, 16,
    14, 13, 19, 18, 17, 2, 13, 14, 15, 11,
    16, 17, 2, 16, 18, 13, 2, 2, 2, 6,
    2, 19, 16, 18, 2, 8, 8, 8, 8, 14,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
    9, 8, 8, 9, 2, 17, 13, 18, 16, 14,
    14, 9, 9, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
)
# PlayMusic(n) streams music\%02d.wav (0x42c2ba) from its start and loops it whole (0x459ec0);
# the imported copies: content/imported/hsl/music/manifest.json (lane MUSIC-IMPORT).
MUSIC_STREAM = "res://content/imported/hsl/music/{track:02d}.ogg"
# actPlayLevelMusic / actPlayMusic / actPlayDefaultLevelMusic: the events that carry a track.
MUSIC_KINDS = ("opening_music", "music_track", "default_level_music")
_SCRIPT_LEVEL = re.compile(r"^(?:story|winfail)(\d+)", re.IGNORECASE)


def level_table_track(level: int) -> int:
    """0x42c1c0: the table track of a level, -1 outside levels 0-99."""
    return LEVEL_MUSIC_TABLE[level] if 0 <= level < len(LEVEL_MUSIC_TABLE) else -1


def music_stream(track: int) -> str:
    """The imported file PlayMusic(track) plays; "" for -1 (the current track keeps playing)."""
    return MUSIC_STREAM.format(track=track) if track >= 0 else ""


def level_table_music(level: int) -> dict[str, Any]:
    """The scene field a loaded battle record plays: EnterLevel's load path (0x42ec10 /
    0x42ebe0) runs PlayLevelMusic after the level change stopped the music, so -1 is silence."""
    track = level_table_track(level)
    return {"track": track, "stream": music_stream(track)}


def script_level(script_id: str) -> int:
    """The level a script runs in (storyNNN, winfailNNN_<status>): actPlayLevelMusic reads it."""
    match = _SCRIPT_LEVEL.match(script_id)
    if match is None:
        raise SystemExit(f"actPlayLevelMusic in {script_id!r}: the script id names no level")
    return int(match.group(1))


def _music_track(kind: str, args: list[str], script_id: str) -> int:
    """original_music.md §1: actPlayMusic N -> N; actPlayLevelMusic -> the table track of the
    script's level; actPlayDefaultLevelMusic L -> the table track of level L."""
    if kind == "opening_music":
        return level_table_track(script_level(script_id))
    try:
        value = int(str(args[0]).strip())
    except (IndexError, ValueError):
        raise SystemExit(f"{script_id}: music action {kind} needs an integer argument, got {args}") from None
    return value if kind == "music_track" else level_table_track(value)


def _music_display_line(kind: str, args: list[str], script_id: str, track: int) -> str:
    played = f"track {track:02d}" if track >= 0 else "-1, the current track keeps playing"
    if kind == "opening_music":
        return f"Play level music: level {script_level(script_id)} table -> {played}"
    if kind == "default_level_music":
        return f"Play default level music: level {args[0]} table -> {played}"
    return f"Play music {played}"


ACTION_KIND = {
    "actPlayLevelMusic": "opening_music",
    "actDelay": "opening_delay",
    "actWalkDispWait": "actor_walk_disp_wait",
    "actMessage": "dialogue_message_id",
    "actSetDeadMessage": "dead_message_registration",
    "actShowSectionName": "section_title_resource",
    "actInsertFailStatus": "fail_status_enable",
    "actInsertEventStatus": "event_status_enable",
    "actShowWinFailStatus": "winfail_board_refresh",
    # Tokens first seen in the STORY052 opening stream. Their kinds name the
    # source intent only; handler timing and coordinate spaces stay unresolved.
    "actSetBGToObject": "background_object_target",
    "actScrollBGToObject": "camera_object_target",
    "actPlaySound": "sound_effect",
    "actInsertObject": "object_insert",
    "actSetPrevInsertObjectWaitRound": "inserted_object_wait_round",
    "actWalkPrevInsertObjectWait": "inserted_object_walk_disp_wait",
    "actInsertWinStatus": "win_status_enable",
    # Tokens first seen in the STORY058 story-only scene (chapter-01 epilogue).
    "actPlayMusic": "music_track",
    "actWalkWait": "actor_walk_wait",
    "actWalk": "actor_walk",
    "actWalkDisp": "actor_walk_disp",
    "actWalkFollow": "actor_walk_follow",
    "actWalkFollowWait": "actor_walk_follow_wait",
    "actWalkAndDelete": "actor_walk_and_delete",
    # STORY060 (second throne-hall scene) adds the blocking variant.
    "actWalkAndDeleteWait": "actor_walk_and_delete_wait",
    "actInsertStoryObject": "story_object_insert",
    "actDarkScreen": "screen_darken",
    "actSetNextPlayLevelEvent": "next_level_event",
    # STORY053 (緹娜's escape) opening tokens: absolute camera positions, the
    # rope-climb shape swap and pixel move, and the escape-zone marker objects.
    "actScrollBGToPos": "camera_position_target",
    "actChangeShape": "actor_shape_change",
    "actRestoreShape": "actor_shape_restore",
    "actMoveDispWait": "actor_move_disp_wait",
    "actInsertShowPosObject": "show_position_marker",
    "actDeleteShowPosObject": "show_position_marker_clear",
    "actSetPrevInsertObjectAdjustLevel": "inserted_object_adjust_level",
}

# Every remaining non-condition token of DATA\ACTION.H (the script VM catalogue;
# actCheck*/actTRUE/actFALSE belong to the winfail interpreter). Argument names
# follow the ACTION.H comment for the opcode (resource-derived); the kind names
# the source intent only. A trailing "..." name collects the remaining arguments.
# category -> presentation status / unresolved sentence, see EXTENDED_CATEGORIES.
EXTENDED_TOKENS: dict[str, tuple[str, str, list[str]]] = {
    # camera
    "actSetBGToPos": ("camera_position_set", "camera", ["x", "y"]),
    "actScrollBGToPosSpeed": ("camera_position_target_speed", "camera", ["x", "y", "speed"]),
    "actScrollBGToRandomPos": ("camera_random_position_target", "camera", ["id"]),
    # music
    "actPlayDefaultLevelMusic": ("default_level_music", "music", ["level"]),
    # actor motion / waits
    "actWaitPlayer": ("actor_action_wait", "actor", ["player_code", "serial"]),
    "actDeleteObject": ("actor_delete", "actor", ["code", "serial"]),
    "actMove": ("actor_move", "motion", ["code", "serial", "x", "y", "speed"]),
    "actMoveWait": ("actor_move_wait", "motion", ["code", "serial", "x", "y", "speed"]),
    "actMoveDisp": ("actor_move_disp", "motion", ["code", "serial", "disp_x", "disp_y", "speed"]),
    "actChangeShapeWait": ("actor_shape_change_wait", "motion", ["code", "serial", "shape_delay", "shape_name", "shape_number"]),
    "actSetUseShapeWait": ("actor_use_shape_wait", "motion", ["code", "serial"]),
    "actWalkToPlayerDisp": ("actor_walk_to_actor_disp", "motion", ["code", "serial", "target_code", "target_serial", "disp_x", "disp_y", "speed"]),
    "actWalkToPlayerDispWait": ("actor_walk_to_actor_disp_wait", "motion", ["code", "serial", "target_code", "target_serial", "disp_x", "disp_y", "speed"]),
    "actSetWaitRound": ("actor_wait_round", "actor", ["code", "serial", "num"]),
    # inserted objects
    "actWalkPrevInsertObject": ("inserted_object_walk_disp", "insert", ["x", "y", "speed"]),
    "actChangePrevInsertObjectID": ("inserted_object_id_change", "insert", ["id"]),
    "actSetPrevInsertObjectFly": ("inserted_object_fly_flag", "insert", ["mode"]),
    "actSetPrevInsertObjectST": ("inserted_object_stamina", "insert", ["st"]),
    "actSetPrevInsertObjectEquip": ("inserted_object_equip", "insert", ["id", "part"]),
    "actWaitPrevInsertPlayer": ("inserted_player_wait", "insert", []),
    "actInsertObjectRandomPos": ("object_insert_random_position", "insert", ["code", "disp_x", "disp_y", "pos_id"]),
    "actInsertStoryObjectRandomPos": ("story_object_insert_random_position", "insert", ["code", "disp_x", "disp_y", "pos_id"]),
    "actInsertStoryObjectWait": ("story_object_insert_wait", "insert", ["code", "x", "y"]),
    "actInsertStoryObjectWaitPos": ("story_object_insert_wait_position", "insert", ["code", "pos_number", "positions..."]),
    "actInsertStoryObjectXRange": ("story_object_insert_x_range", "insert", ["code", "x", "y", "x_number"]),
    "actInsertRandomObject": ("random_object_insert", "insert", ["args..."]),
    "actInsertLevelUpStar": ("level_up_star_insert", "insert", ["sound_id"]),
    # positional object edits
    "actDeletePosObject": ("position_object_delete", "position", ["x", "y", "range", "proc_code"]),
    "actDeleteRandomPosObject": ("random_position_object_delete", "position", ["id", "range", "proc_code"]),
    "actDeletePosPlayerXRange": ("position_actor_delete_x_range", "position", ["x", "y", "x_number", "proc_code"]),
    "actChangePosObjectProcCode": ("position_object_proc_code_change", "position", ["x", "y", "range", "proc_code", "new_proc_code"]),
    "actSetRandomPos": ("random_position_set", "position", ["num", "positions..."]),
    "actRandomSetSysArrivePos": ("system_arrive_position_random", "position", ["num", "positions..."]),
    # dialogue
    "actMessageIfExist": ("dialogue_message_if_exist", "dialogue", ["player_code", "serial", "message_id", "message_id_false", "check_number", "check_player_codes..."]),
    "actShapeMessage": ("shape_message", "dialogue", ["shape_file", "name", "message_id"]),
    "actSelectInsertEvent": ("event_select_insert", "dialogue", ["id", "serial", "num", "choices..."]),
    # player / unit state
    "actSetPlayerUndead": ("player_undead_flag", "state", ["code", "serial", "mode"]),
    "actSetPlayerMode": ("player_mode_set", "state", ["code", "serial", "mode", "flag"]),
    "actSetPlayerExecMode": ("player_exec_mode", "state", ["code", "serial", "mode"]),
    "actSetPlayerFixPos": ("player_fix_position", "state", ["code", "serial", "x", "y", "distance"]),
    "actSetPlayerWalkShape": ("player_walk_shape", "state", ["player_id", "serial"]),
    "actSetPlayerFly": ("player_fly_flag", "state", ["code", "serial", "mode"]),
    "actSetPlayerNoAttack": ("player_no_attack_flag", "state", ["player_id", "serial", "mode"]),
    "actSetPlayerPosToRandom0": ("player_position_random0", "state", ["player_id", "serial"]),
    "actSetPlayerName": ("player_name_set", "state", ["player_id", "serial", "name", "job_name"]),
    "actChangePlayerID": ("player_id_change", "state", ["player_old_id", "serial", "new_id"]),
    "actDeletePlayerCode": ("player_code_delete", "state", ["id", "mode"]),
    "actKeepPlayerST": ("player_stamina_keep", "state", []),
    "actAdjustAllPlayerLevel": ("player_level_adjust_all", "state", []),
    "actPlayerJobUpProcess": ("player_job_up_process", "state", ["player_id", "serial"]),
    "actUseItem": ("item_use", "state", ["code", "serial", "item_id"]),
    "actGetItem": ("item_grant", "state", ["item_id", "number"]),
    # win/fail/event status edits (enable variants are mapped above)
    "actDeleteWinStatus": ("win_status_disable", "status", ["code"]),
    "actDeleteFailStatus": ("fail_status_disable", "status", ["code"]),
    "actDeleteEventStatus": ("event_status_disable", "status", ["code"]),
    "actReplaceWinStatus": ("win_status_replace", "status", ["old_code", "new_code"]),
    "actReplaceFailStatus": ("fail_status_replace", "status", ["old_code", "new_code"]),
    "actReplaceEventStatus": ("event_status_replace", "status", ["old_code", "new_code"]),
    "actExecWinFailProcess": ("winfail_process_exec", "status", []),
    # screen / flow
    "actDeleteDarkScreen": ("screen_darken_clear", "screen", []),
    "actEarthQuake": ("earthquake", "screen", ["delay"]),
    "actPlayMovie": ("movie_play", "screen", ["movie_code"]),
    "actSetDoublePageMode": ("double_page_mode", "screen", ["mode"]),
    "actSetWalkSoundMode": ("walk_sound_mode", "screen", ["mode"]),
    "actDetectRoundDispDisp": ("round_disp_detect", "screen", ["num"]),
    "actOver": ("script_over", "flow", []),
    "actDEMO": ("demo", "flow", []),
    "actSetNextPlayLevelGetOverEvent": ("next_level_get_over_event", "flow", ["level"]),
    "actSetOverFlag": ("game_over_flag", "flow", ["flag"]),
    "actAddOverScore": ("game_over_score_add", "flow", ["id", "score"]),
    "actEnterStorageWindow": ("storage_window_enter", "flow", []),
    # town / big map
    "actSetTownExecEvent": ("town_exec_event", "town", ["town_id", "event"]),
    "actSetTownExitExecEvent": ("town_exit_exec_event", "town", ["town_id", "event"]),
    "actAddTE": ("town_event_add", "town", ["town_id", "parent", "num", "children..."]),
    "actDeleteTE": ("town_event_delete", "town", ["town_id", "parent", "num", "children..."]),
    "actSetBMWalkToPoint": ("bigmap_walk_to_point", "bigmap", ["from_point_id", "point_id"]),
    "actSetBMWalkerPlayerID": ("bigmap_walker_player_id", "bigmap", ["player_id"]),
    "actBMSetPointMode": ("bigmap_point_mode", "bigmap", ["id", "mode"]),
    "actBMSetTrackMode": ("bigmap_track_mode", "bigmap", ["id", "mode"]),
    "actBMSetPointFlag": ("bigmap_point_flag_set", "bigmap", ["id", "flag"]),
    "actBMSetTrackFlag": ("bigmap_track_flag_set", "bigmap", ["id", "flag"]),
    "actBMClearPointFlag": ("bigmap_point_flag_clear", "bigmap", ["id", "flag"]),
    "actBMClearTrackFlag": ("bigmap_track_flag_clear", "bigmap", ["id", "flag"]),
    "actBMSetPointEvent": ("bigmap_point_event", "bigmap", ["id", "event", "flag"]),
    "actBMSetPointEncounterRatio": ("bigmap_point_encounter_ratio", "bigmap", ["id", "ratio"]),
    "actBMSetShowTrackPoint": ("bigmap_show_track_point", "bigmap", ["id"]),
}
ACTION_KIND.update({name: spec[0] for name, spec in EXTENDED_TOKENS.items()})
EXTENDED_KIND_TO_NAME = {spec[0]: name for name, spec in EXTENDED_TOKENS.items()}

# (presentation_status, unresolved sentence, display prefix) per extended category.
EXTENDED_CATEGORIES: dict[str, tuple[str, str, str]] = {
    "camera": ("camera_token_only_target_semantics_unresolved",
               "view anchor, scroll curve and clamping are unresolved; the remake reads x,y as the view's top-left map pixel",
               "Camera position token"),
    "music": ("music_track_resolved",
              "the track is resolved from the original level music table", "Play default level music"),
    "actor": ("script_token_present_provisional_motion",
              "bound actor instance lookup and the original wait/delete side effects are unresolved", "Actor token"),
    "motion": ("script_token_present_provisional_motion",
               "pixel targets, speed unit and blocking behaviour are unresolved", "Actor motion token"),
    "insert": ("insert_token_only_lifecycle_unresolved",
               "previously inserted object lifecycle, faction and pixel coordinate space are unresolved", "Inserted object token"),
    "position": ("position_token_only_scope_unresolved",
                 "which objects the x,y/range/proc-code selector hits is unresolved", "Position object token"),
    "dialogue": ("message_id_only_text_unresolved",
                 "existence check, alternate message and box layout are unresolved; only message ids are preserved", "Conditional dialogue token"),
    "state": ("state_token_recorded_no_handler",
              "engine-side unit state change is recorded only; no remake handler applies it", "Unit state token"),
    "status": ("timeline_event_only",
               "status/UI side effects remain handler-level evidence tasks", "Win/fail status edit token"),
    "screen": ("screen_token_recorded_no_handler",
               "screen effect duration and appearance are unresolved", "Screen effect token"),
    "flow": ("flow_token_recorded_no_handler",
             "level/game flow side effect is recorded only", "Flow token"),
    "town": ("town_token_recorded_no_handler",
             "town/event table edits belong to the world map layer, which is not remade", "Town event token"),
    "bigmap": ("bigmap_token_recorded_no_handler",
               "big-map point/track edits belong to the world map layer, which is not remade", "Big map token"),
}

_ACTION_NAMES_LOWER = {name.lower(): name for name in ACTION_KIND}


def canonical_action_name(name: str) -> str:
    """Script tokens are matched case-insensitively (STORY scripts spell actMEssage
    twice); the canonical spelling is the ACTION.H one used by ACTION_KIND."""
    return _ACTION_NAMES_LOWER.get(name.lower(), name)


# actPlayMovie's argument -> the imported film (content/imported/hsl/movie/manifest.json).
# The corpus has one call, WINFAIL059's actPlayMovie 140 in the finale's win section, and
# movie.pak holds one ending film (end.ani); the handler's argument semantics are not
# located, so 140 -> end is a provisional reading. The intro (start.ani) has no script token.
MOVIE_BY_CODE: dict[int, str] = {140: "end"}


def movie_name_for_code(code: Any) -> str:
    """The imported film an actPlayMovie argument names ("" when unmapped)."""
    try:
        return MOVIE_BY_CODE.get(int(str(code).strip()), "")
    except ValueError:
        return ""


def _extended_params(name: str, args: list[str]) -> dict[str, Any]:
    """Name the arguments after the ACTION.H comment; numeric strings become ints,
    a trailing \"...\" name collects the rest as a list."""
    spec = EXTENDED_TOKENS.get(name)
    if spec is None:
        return {}
    params: dict[str, Any] = {}
    names = spec[2]
    for index, arg_name in enumerate(names):
        if arg_name.endswith("..."):
            params[arg_name[:-3]] = [_scalar(value) for value in args[index:]]
            break
        if index < len(args):
            params[arg_name] = _scalar(args[index])
    if len(args) > len(names) and not (names and names[-1].endswith("...")):
        params["extra_args"] = [_scalar(value) for value in args[len(names):]]
    return params


def _scalar(value: str) -> Any:
    text = str(value).strip()
    try:
        return int(text, 10)
    except ValueError:
        return text


ACTOR_TOKEN_ACTIONS = {
    "actWalkDispWait", "actMessage", "actSetDeadMessage", "actSetBGToObject", "actScrollBGToObject",
    "actWalkWait", "actWalk", "actWalkDisp", "actWalkFollow", "actWalkFollowWait", "actWalkAndDelete", "actWalkAndDeleteWait",
    "actChangeShape", "actRestoreShape", "actMoveDispWait",
    # extended tokens whose first two arguments are [player code][serial]
    "actWaitPlayer", "actDeleteObject", "actMove", "actMoveWait", "actMoveDisp", "actChangeShapeWait", "actSetUseShapeWait",
    "actWalkToPlayerDisp", "actWalkToPlayerDispWait", "actSetWaitRound", "actMessageIfExist", "actSetPlayerUndead",
    "actSetPlayerMode", "actSetPlayerExecMode", "actSetPlayerFixPos", "actSetPlayerWalkShape", "actSetPlayerFly",
    "actSetPlayerNoAttack", "actSetPlayerPosToRandom0", "actSetPlayerName", "actChangePlayerID", "actPlayerJobUpProcess",
    "actUseItem",
}
WALK_KINDS = {"actor_walk_wait", "actor_walk", "actor_walk_disp", "actor_walk_follow", "actor_walk_follow_wait",
              "actor_walk_and_delete", "actor_walk_and_delete_wait"}

# Story-only levels end with a scene handoff instead of first player control.
END_MARKERS = {
    "battle": ("first_control_ready", "first_control_marker", "First-control marker after {stem} opening action queue",
               ["exact transition from final {stem} action to first player-control frame",
                "complete pre-control enemy/friendly movement not represented by {stem} action tokens"]),
    "story": ("scene_end_ready", "scene_end_marker", "Scene-end marker after {stem} story action queue",
              ["exact transition from the final {stem} action to the next level entry",
               "original fade/level-load timing after the story script ends"]),
}


def compile_opening_timeline(story_path: Path, message_evidence_path: Path | None = None) -> dict[str, Any]:
    return compile_documents(_load_json(story_path), story_path.as_posix(), _load_message_evidence(message_evidence_path),
                             message_evidence_path.as_posix() if message_evidence_path else "")


def compile_documents(story: dict[str, Any], story_path: str, messages: dict[str, Any] | None, message_evidence_path: str = "") -> dict[str, Any]:
    """The compiler over in-memory documents (a tracked seed or script IR and its resolved
    message evidence); compile_opening_timeline reads them from disk, the authored level
    assembler (hsltools.levels.authored) renders them in one pass."""
    level_kind = "battle"
    if str(story.get("schema", "")) == SEED_SCHEMA:
        script_id, source_file, action_chain, source_schema = _action_chain_from_seed(story)
        level_kind = str(story.get("level_kind", "battle"))
    else:
        script_id = str(story.get("id", "story051"))
        source_file = str(story.get("source_file", "STORY051.TXT"))
        action_chain = story.get("action_chain", [])
        source_schema = str(story.get("schema", ""))
    if not isinstance(action_chain, list):
        raise SystemExit(f"story action_chain must be a list: {story_path}")

    events: list[dict[str, Any]] = []
    for action in action_chain:
        if not isinstance(action, dict):
            continue
        events.append(_event_from_action(action, script_id, source_file, messages))

    source_stem = Path(source_file).stem
    marker_id, marker_kind, marker_line, marker_unresolved = END_MARKERS[level_kind if level_kind in END_MARKERS else "battle"]
    events.append(
        {
            "id": marker_id,
            "kind": marker_kind,
            "source_script": "BattleSceneRuntime",
            "source_file": "tests/capture_battle_scene_dev_interaction_harness.gd",
            "source_action_index": None,
            "source_chain_index": None,
            "script_action_name": marker_id,
            "primary": marker_id,
            "args": [],
            "source_token": marker_id,
            "display_line": marker_line.format(stem=source_stem),
            "evidence_tier": "godot-rendered-provisional",
            "presentation_status": "handoff_marker_only",
            "synthetic": True,
            "unresolved_semantics": [item.format(stem=source_stem) for item in marker_unresolved],
        }
    )

    report: dict[str, Any] = {
        "schema": SCHEMA,
        "source_script": script_id,
        "source_file": source_file,
        "source_path": story_path,
        "source_schema": source_schema,
        "level_kind": level_kind,
        "evidence_tier": "resource-derived",
        "event_count": len(events),
        "events": events,
        "contract": {
            "purpose": "Opening presentation event queue for BattleSceneRuntime",
            "sequence_source": f"{source_stem} action_chain order, plus one provisional first-control handoff marker",
            "not_proven": [
                "original message box layout",
                "message box layout",
                "exact delay time scale",
                "complete enemy gate-entry choreography",
                "camera curve",
                "actor foot anchors and path timing",
                "handler side effects beyond preserved action tokens",
            ],
        },
    }
    if messages is not None:
        report["message_evidence_path"] = message_evidence_path
        report["contract"]["not_proven"].extend(
            [
                "message playback timing, portrait binding and blocking behavior",
                "inserted object lifetime, faction and walk target coordinate space",
                "background/camera object target semantics",
            ]
        )
    return report


def _action_chain_from_seed(seed: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]], str]:
    level_code = str(seed.get("level_code") or f"{int(seed.get('level', 0)):03d}")
    script_id = f"story{level_code}"
    story = seed.get("scripts", {}).get("story", {})
    source_member = str(seed.get("sources", {}).get("story", {}).get("member", f"STORY{level_code}.TXT"))
    source_file = source_member.split("\\")[-1]
    chain: list[dict[str, Any]] = []
    index = 0
    action_index = 0
    for section in story.get("sections", []):
        if not isinstance(section, dict):
            continue
        for action in section.get("actions", []):
            if not isinstance(action, dict):
                continue
            commands = action.get("chain", [])
            for chain_index, command in enumerate(commands):
                if not isinstance(command, dict):
                    continue
                chain.append(
                    {
                        "index": index,
                        "script_id": script_id,
                        "source_file": source_file,
                        "section_index": int(section.get("index", 0)),
                        "section_name": str(section.get("name", "")),
                        "action_index": action_index,
                        "chain_index": chain_index,
                        "primary": str(action.get("primary", command.get("name", ""))),
                        "name": str(command.get("name", "")),
                        "args": [str(arg) for arg in command.get("args", [])],
                        "evidence_tier": str(seed.get("evidence_tier", "resource-derived")),
                        "unresolved_semantics": [
                            "seed action record preserves original order and args; handler behavior is not fully mapped"
                        ],
                    }
                )
                index += 1
            action_index += 1
    return script_id, source_file, chain, str(seed.get("schema", ""))


# Message evidence the compiler may resolve text from: the imported RESOURCE.TXT table or a
# level's authored messages (content/authored/levelNNN/messages.json).
RESOLVED_MESSAGE_STATUSES = ("resolved_from_resource_table", "resolved_from_authored_messages")


def _load_message_evidence(path: Path | None) -> dict[str, Any] | None:
    if path is None:
        return None
    evidence = _load_json(path)
    if evidence.get("message_text_status") not in RESOLVED_MESSAGE_STATUSES:
        raise SystemExit(f"message evidence is unresolved: {path}")
    return evidence


def _event_from_action(
    action: dict[str, Any],
    script_id: str,
    source_file: str,
    messages: dict[str, Any] | None,
) -> dict[str, Any]:
    raw_name = str(action.get("name", ""))
    name = canonical_action_name(raw_name)
    kind = ACTION_KIND.get(name, "script_action")
    source_index = int(action.get("index", 0))
    action_index = int(action.get("action_index", source_index))
    chain_index = int(action.get("chain_index", 0))
    args = [str(arg) for arg in action.get("args", [])]
    event_id = f"{script_id}_{source_index:02d}_{kind}"
    event: dict[str, Any] = {
        "id": event_id,
        "kind": kind,
        "source_script": str(action.get("script_id", script_id)),
        "source_file": str(action.get("source_file", source_file)),
        "source_action_index": action_index,
        "source_chain_index": chain_index,
        "script_action_name": name,
        "primary": str(action.get("primary", name)),
        "args": args,
        "source_token": _source_token(name, args),
        "display_line": _display_line(kind, name, args),
        "message_id": _message_id(name, args),
        "actor_token": args[0] if args and name in ACTOR_TOKEN_ACTIONS else "",
        "evidence_tier": str(action.get("evidence_tier", "resource-derived")),
        "presentation_status": _presentation_status(kind),
        "synthetic": False,
        "unresolved_semantics": _unresolved_semantics(kind, action),
    }
    if kind in MUSIC_KINDS:
        # Resolved here once; the coordinator plays `stream` from its start ("" keeps the current track).
        track = _music_track(kind, args, event["source_script"])
        event["display_line"] = _music_display_line(kind, args, event["source_script"], track)
        event["track"] = track
        event["stream"] = music_stream(track)
    if kind == "dialogue_message_id":
        # defNoOne is the script's speakerless narration token.
        event["narration"] = event["actor_token"] == "defNoOne"
    if raw_name != name:
        event["script_action_spelling"] = raw_name  # e.g. actMEssage in the source script
    if name in EXTENDED_TOKENS:
        event["params"] = _extended_params(name, args)
        if kind == "movie_play":
            event["params"]["movie"] = movie_name_for_code(args[0]) if args else ""
        if kind == "dialogue_message_if_exist":
            event["narration"] = event["actor_token"] == "defNoOne"
            false_id = str(event["params"].get("message_id_false", ""))
            event["message_id_false"] = false_id if false_id.isdigit() and int(false_id) > 0 else ""
            if messages is not None and event["message_id_false"]:
                false_text = messages.get("messages", {}).get(event["message_id_false"])
                if false_text is None:
                    raise SystemExit(f"message id {event['message_id_false']} missing from message evidence")
                event["message_text_false"] = false_text
    if messages is not None and event["message_id"]:
        text = messages.get("messages", {}).get(event["message_id"])
        if text is None:
            raise SystemExit(f"message id {event['message_id']} missing from message evidence")
        event["message_text"] = text
        event["speaker_name"] = str(messages.get("speaker_names", {}).get(event["actor_token"], ""))
        event["message_text_evidence_tier"] = str(messages.get("evidence_tier", "resource-derived"))
        if kind in {"dialogue_message_id", "dialogue_message_if_exist"}:
            event["presentation_status"] = "message_text_resolved_layout_unresolved"
        event["unresolved_semantics"] = [
            "message box layout, playback timing and portrait binding are unresolved"
            if item == "message text source is unresolved; only message id is preserved" else item
            for item in event["unresolved_semantics"]
        ]
    return event


def _source_token(name: str, args: list[str]) -> str:
    return f"{name}({','.join(args)})"


def _display_line(kind: str, name: str, args: list[str]) -> str:
    if kind == "opening_delay":
        return f"Opening delay token {args[0] if args else '?'}"
    if kind == "actor_walk_disp_wait":
        return "Actor walk/display wait token: " + _source_token(name, args)
    if kind == "dialogue_message_id":
        return "Dialogue message id " + (args[2] if len(args) >= 3 else "?")
    if kind == "dead_message_registration":
        return "Register Leonard defeat/death message token"
    if kind == "section_title_resource":
        return "Show section title resource " + (args[0] if args else "?")
    if kind in {"fail_status_enable", "event_status_enable", "win_status_enable"}:
        return f"Enable {kind.replace('_enable', '')} token {args[0] if args else '?'}"
    if kind == "winfail_board_refresh":
        return "Refresh/show win/fail status board"
    if kind == "background_object_target":
        return "Set background view to object token: " + _source_token(name, args)
    if kind == "camera_object_target":
        return "Scroll background to object token: " + _source_token(name, args)
    if kind == "sound_effect":
        return "Play sound resource " + (args[0] if args else "?")
    if kind == "object_insert":
        return "Insert script object token: " + _source_token(name, args)
    if kind == "inserted_object_wait_round":
        return f"Inserted object wait-round token {args[0] if args else '?'}"
    if kind == "inserted_object_walk_disp_wait":
        return "Inserted object walk/display wait token: " + _source_token(name, args)
    if kind in WALK_KINDS:
        return "Actor walk token: " + _source_token(name, args)
    if kind == "story_object_insert":
        return "Insert story object token: " + _source_token(name, args)
    if kind == "screen_darken":
        return "Darken screen token"
    if kind == "next_level_event":
        return f"Set next play level/event token {','.join(args)}"
    if kind in EXTENDED_KIND_TO_NAME:
        category = EXTENDED_TOKENS[EXTENDED_KIND_TO_NAME[kind]][1]
        return EXTENDED_CATEGORIES[category][2] + ": " + _source_token(name, args)
    return _source_token(name, args)


def _message_id(name: str, args: list[str]) -> str:
    if name in {"actMessage", "actMessageIfExist"} and len(args) >= 3:
        return args[2]
    if name == "actSetDeadMessage" and len(args) >= 3:
        return args[2]
    if name == "actShapeMessage" and len(args) >= 3:
        return args[2]
    return ""


def _presentation_status(kind: str) -> str:
    if kind in MUSIC_KINDS:
        return "music_track_resolved"
    if kind == "actor_walk_disp_wait":
        return "script_token_present_provisional_motion"
    if kind == "dialogue_message_id":
        return "message_id_only_text_unresolved"
    if kind == "opening_delay":
        return "delay_token_only_time_scale_unresolved"
    if kind in {"background_object_target", "camera_object_target"}:
        return "camera_token_only_target_semantics_unresolved"
    if kind == "sound_effect":
        return "sound_token_only_mix_unresolved"
    if kind in {"object_insert", "inserted_object_wait_round", "inserted_object_walk_disp_wait", "story_object_insert"}:
        return "insert_token_only_lifecycle_unresolved"
    if kind in WALK_KINDS:
        return "script_token_present_provisional_motion"
    if kind == "next_level_event":
        return "level_flow_token_consumed_by_campaign"
    if kind in EXTENDED_KIND_TO_NAME:
        return EXTENDED_CATEGORIES[EXTENDED_TOKENS[EXTENDED_KIND_TO_NAME[kind]][1]][0]
    return "timeline_event_only"


def _unresolved_semantics(kind: str, action: dict[str, Any]) -> list[str]:
    base = [
        "handler behavior is not fully mapped",
        "runtime timing is not proven by this static action token",
    ]
    if kind in MUSIC_KINDS:
        # The handlers are mapped (original_music.md §1); only the coordinator's pacing is remake.
        base = ["runtime timing is not proven by this static action token"]
    elif kind == "actor_walk_disp_wait":
        base.extend(
            [
                "coordinate arguments are preserved but not yet mapped to final world path semantics",
                "walk speed and facing sequence remain unresolved",
            ]
        )
    elif kind == "dialogue_message_id":
        base.append("message text source is unresolved; only message id is preserved")
    elif kind == "opening_delay":
        base.append("delay unit to seconds/frame mapping is unresolved")
    elif kind == "movie_play":
        base.append("the argument's meaning is unlocated; 140 -> movie.pak end.ani is a provisional reading (the corpus's only call, in the finale's win section)")
    elif kind in {"fail_status_enable", "event_status_enable", "winfail_board_refresh", "win_status_enable"}:
        base.append("status/UI side effects remain handler-level evidence tasks")
    elif kind in {"background_object_target", "camera_object_target"}:
        base.append("object target instance, camera framing and blocking behavior are unresolved")
    elif kind == "sound_effect":
        base.append("sound trigger timing and mixing relative to the following token are unresolved")
    elif kind == "object_insert":
        base.append("inserted object faction, lifetime and pixel coordinate space are unresolved")
    elif kind == "inserted_object_wait_round":
        base.append("wait-round unit and its effect on the inserted object are unresolved")
    elif kind == "inserted_object_walk_disp_wait":
        base.append("walk target is a non-grid-aligned pixel candidate; path, speed and facing are unresolved")
    elif kind in WALK_KINDS:
        base.append("absolute/relative pixel targets, follow offsets, speed token and delete timing are unresolved")
    elif kind == "story_object_insert":
        base.append("story object process (defProcObjectMove) motion and lifetime are unresolved")
    elif kind == "screen_darken":
        base.append("fade duration and colour are unresolved")
    elif kind == "next_level_event":
        base.append("level/event transition timing is unresolved; the campaign consumes the pair")
    elif kind in EXTENDED_KIND_TO_NAME:
        base.append(EXTENDED_CATEGORIES[EXTENDED_TOKENS[EXTENDED_KIND_TO_NAME[kind]][1]][1])
    for item in action.get("unresolved_semantics", []):
        item_text = str(item)
        if item_text not in base:
            base.append(item_text)
    return base


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data: Any = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object: {path}")
    return data


DEFAULT_TIMELINE = Path("content/imported/hsl/chapter01/opening_timeline.json")

COMMON_REQUIRED_KINDS = [
    "actor_walk_disp_wait",
    "dialogue_message_id",
    "section_title_resource",
    "fail_status_enable",
    "event_status_enable",
    "winfail_board_refresh",
]

# Each profile states what the compiled queue of that original script must keep.
PROFILES: dict[str, dict[str, Any]] = {
    "story051": {
        "first_kind": "opening_music",
        "min_events": 18,
        "required_kinds": COMMON_REQUIRED_KINDS,
        "required_message_ids": {"363", "364", "365", "366", "367", "1101"},
        "message_text_required": False,
    },
    "story052": {
        "first_kind": "background_object_target",
        "min_events": 57,
        "required_kinds": COMMON_REQUIRED_KINDS
        + [
            "opening_music",
            "sound_effect",
            "camera_object_target",
            "object_insert",
            "inserted_object_wait_round",
            "inserted_object_walk_disp_wait",
            "win_status_enable",
            "dead_message_registration",
        ],
        "required_message_ids": {"379", "380", "381", "383", "384", "385", "386", "387", "388", "389", "390", "391"},
        "message_text_required": True,
    },
    "story058": {
        "first_kind": "background_object_target",
        "min_events": 50,
        "end_kind": "scene_end_marker",
        "required_kinds": [
            "music_track",
            "camera_object_target",
            "actor_walk_wait",
            "actor_walk_disp_wait",
            "dialogue_message_id",
            "story_object_insert",
            "actor_walk_disp",
            "sound_effect",
            "actor_walk",
            "actor_walk_follow",
            "actor_walk_follow_wait",
            "actor_walk_and_delete",
            "screen_darken",
            "next_level_event",
        ],
        "required_message_ids": {str(i) for i in range(658, 676)},
        "message_text_required": True,
    },
    "story060": {
        "first_kind": "background_object_target",
        "min_events": 38,
        "end_kind": "scene_end_marker",
        "required_kinds": [
            "music_track",
            "camera_object_target",
            "actor_walk_wait",
            "dialogue_message_id",
            "actor_walk",
            "actor_walk_follow",
            "actor_walk_follow_wait",
            "actor_walk_and_delete",
            "actor_walk_and_delete_wait",
            "next_level_event",
        ],
        "required_message_ids": {str(i) for i in range(676, 693)} | {"380"},
        "message_text_required": True,
    },
    "story053": {
        "first_kind": "camera_position_target",
        "min_events": 40,
        "end_kind": "first_control_marker",
        "required_kinds": [
            "music_track",
            "camera_object_target",
            "dialogue_message_id",
            "actor_walk_and_delete_wait",
            "story_object_insert",
            "actor_walk_disp_wait",
            "actor_shape_change",
            "actor_move_disp_wait",
            "actor_shape_restore",
            "object_insert",
            "inserted_object_adjust_level",
            "inserted_object_walk_disp_wait",
            "dead_message_registration",
            "section_title_resource",
            "show_position_marker",
            "show_position_marker_clear",
            "win_status_enable",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
            "opening_music",
        ],
        "required_message_ids": {"698", "699", "700", "701", "702", "703"},
        "message_text_required": True,
    },
    "story001": {
        # First main-chapter battle: the mercenaries haggle with the villagers, the
        # raiders arrive, the title and both win/fail statuses are enabled before
        # the raider chief's six-unit advance and the final exchange.
        "first_kind": "music_track",
        "min_events": 80,
        "end_kind": "first_control_marker",
        "required_kinds": [
            "opening_delay",
            "dialogue_message_id",
            "actor_walk_disp_wait",
            "actor_walk_wait",
            "actor_walk_disp",
            "dead_message_registration",
            "section_title_resource",
            "win_status_enable",
            "fail_status_enable",
            "winfail_board_refresh",
            "opening_music",
        ],
        "required_message_ids": {str(i) for i in range(705, 733)} | {"380"},
        "message_text_required": True,
    },
    "story002": {
        # 戈爾山道: the raiders flee along the road, the mercenaries catch up, the title
        # and the event / fail statuses are enabled before first control.
        "first_kind": "opening_music",
        "min_events": 30,
        "end_kind": "first_control_marker",
        "required_kinds": [
            "opening_delay",
            "dialogue_message_id",
            "actor_walk",
            "actor_walk_wait",
            "camera_object_target",
            "dead_message_registration",
            "section_title_resource",
            "event_status_enable",
            "fail_status_enable",
            "winfail_board_refresh",
            "opening_music",
        ],
        "required_message_ids": {str(i) for i in range(750, 758)},
        "message_text_required": True,
    },
    "story003": {
        # 盜賊洞窟: 漢克斯 is set hostile / undead by script, the party walks in from
        # the west edge, two raiders come to meet them, the title and the fail /
        # event statuses are enabled before first control.
        "first_kind": "opening_music",
        "min_events": 30,
        "end_kind": "first_control_marker",
        "required_kinds": [
            "opening_delay",
            "player_mode_set",
            "player_undead_flag",
            "dialogue_message_id",
            "actor_walk",
            "actor_walk_wait",
            "dead_message_registration",
            "section_title_resource",
            "event_status_enable",
            "fail_status_enable",
            "winfail_board_refresh",
            "opening_music",
        ],
        "required_message_ids": {str(i) for i in range(828, 834)},
        "message_text_required": True,
    },
    "story005": {
        # 呼嘯平原: the camera locks on 雷歐納德, the party walks to the middle of the
        # plain, wing warriors and 038 close in from every edge, three lines, title.
        "first_kind": "background_object_target",
        "min_events": 30,
        "required_kinds": [
            "opening_music",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "section_title_resource",
            "win_status_enable",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
        ],
        "required_message_ids": {"899", "900", "901"},
        "message_text_required": True,
    },
    "story006": {
        # 席達鎮: the camera frames the east gate, the party is inserted and walks in,
        # three soldiers and the captain follow, the captain speaks, title.
        "first_kind": "camera_position_target",
        "min_events": 50,
        "required_kinds": [
            "opening_music",
            "opening_delay",
            "story_object_insert",
            "actor_walk",
            "object_insert",
            "inserted_object_walk_disp",
            "inserted_object_wait_round",
            "player_level_adjust_all",
            "dead_message_registration",
            "dialogue_message_id",
            "section_title_resource",
            "win_status_enable",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
        ],
        "required_message_ids": {"950", "951", "952"},
        "message_text_required": True,
    },
    "story007": {
        # 寧靜之森: the camera frames the south edge, the party walks north into the
        # forest, two lines, 036 / 037 / 038 pour in from every edge, the last line, title.
        "first_kind": "camera_position_target",
        "min_events": 44,
        "required_kinds": [
            "opening_music",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "section_title_resource",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
        ],
        "required_message_ids": {"1007", "1008", "1009"},
        "message_text_required": True,
    },
    "story012": {
        # 巴瀚納海峽: track 9, the party on deck in the storm (雪拉 / 雷特 / 嚎 / 琥 banter),
        # rain controllers and sound, the 038 boarders climb aboard by displacement
        # walks, 雷特's challenge, title and win／fail board.
        "first_kind": "music_track",
        "min_events": 80,
        "required_kinds": [
            "opening_music",
            "opening_delay",
            "actor_walk_disp",
            "actor_walk_disp_wait",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "story_object_insert",
            "sound_effect",
            "section_title_resource",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
        ],
        "required_message_ids": {"1701", "1702", "1703", "1704", "1705", "1706", "1707", "1708", "1709", "1710", "728"},
        "message_text_required": True,
    },
    # lane ch2a
    "story013": {
        # 龍之息 火山: level music, the nine-slot party walks up from the south edge, 雪拉 and 雷歐納德 spot the light,
        # six 051 and three 050 creatures are inserted (the 050 with WALK0021), 克羅蒂 sends 雷歐納德 on, title, win／fail board.
        "first_kind": "opening_music",
        "min_events": 91,
        "required_kinds": ["opening_delay", "camera_position_target", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "object_insert", "inserted_object_wait_round", "inserted_object_walk_disp_wait", "actor_walk_disp_wait", "sound_effect", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "show_position_marker", "winfail_board_refresh", "show_position_marker_clear"],
        "required_message_ids": {"1782", "1783", "1784", "1785", "1786", "1834", "1787"},
        "message_text_required": True,
    },
    "story015": {
        # 深淵之沼: track 9, the camera on 雷歐納德, the swamp banter (雪拉 / 雷歐納德 / 雷特), level music, the 038 / 037 / 033
        # creatures close in by displacement walks, 雷特's last line, title and fail／event statuses.
        "first_kind": "music_track",
        "min_events": 42,
        "required_kinds": ["camera_object_target", "opening_delay", "dialogue_message_id", "opening_music", "actor_walk_disp", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"1794", "1795", "1796", "1797", "1798", "1799", "1017", "1800"},
        "message_text_required": True,
    },
    "story017": {
        # 艾瓦台地: level music, 克里夫 and his workers are chased by the mine creatures, the camera scrolls to the
        # party walking in from the east edge, two lines, title and fail／event statuses.
        "first_kind": "opening_music",
        "min_events": 53,
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_disp", "actor_walk_disp_wait", "camera_position_target", "actor_walk", "actor_walk_wait", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"1359", "1360", "1361", "1362", "1363"},
        "message_text_required": True,
    },
    "story018": {
        # 那可那魯邊境: track 9, the six-member party walks up to the gate, shows the pass, the door 100 is deleted
        # (OPEN0002) and re-inserted as obj_Story_Level_Door (CLOSE001), the guards call for support and spread out,
        # the party regroups, title, statuses, escape markers, level music.
        "first_kind": "music_track",
        "min_events": 118,
        "required_kinds": ["opening_delay", "actor_walk", "actor_walk_wait", "dialogue_message_id", "camera_position_target", "sound_effect", "actor_delete", "camera_object_target", "actor_walk_disp", "actor_walk_disp_wait", "object_insert", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "show_position_marker", "winfail_board_refresh", "opening_music", "show_position_marker_clear"],
        "required_message_ids": {str(i) for i in range(1436, 1450)} | {"774"},
        "message_text_required": True,
    },
    "story019": {
        # 利魯瑪山地: track 9, 雷特 alone walks in, four 041 soldiers surround him and call him a traitor, their
        # dead messages, title, fail／event statuses, level music.
        "first_kind": "music_track",
        "min_events": 39,
        "required_kinds": ["opening_delay", "actor_walk_wait", "camera_position_target", "actor_walk", "dead_message_registration", "dialogue_message_id", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "opening_music"],
        "required_message_ids": {str(i) for i in range(1457, 1464)} | {"1487"},
        "message_text_required": True,
    },
    "story021": {
        # 回音之谷: level music, the eight-slot party walks to the middle of the valley, the 041 / 043 / 038 line
        # sweeps in from the east by displacement walks, three lines, title and fail／event statuses.
        "first_kind": "opening_music",
        "min_events": 66,
        "required_kinds": ["opening_delay", "camera_position_target", "actor_walk", "actor_walk_wait", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"1548", "1549", "1550"},
        "message_text_required": True,
    },
    "story022": {
        # 尼布魯瀑布: track 8, the view is set to the west edge, the nine-slot party walks in, 緹娜 and 雷特 admire the
        # fall, the camera follows the 041 / 043 patrols walking in from the east, the patrol recognises 雷特, title,
        # statuses, level music.
        "first_kind": "music_track",
        "min_events": 67,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "camera_object_target", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "opening_music"],
        "required_message_ids": {str(i) for i in range(2405, 2411)},
        "message_text_required": True,
    },
    "story024": {
        # 哈莫特沙漠: level music, the eight-slot party walks down from the north edge, the Wosfita captain 024
        # denounces 雷歐納德, title and fail／event statuses.
        "first_kind": "opening_music",
        "min_events": 43,
        "required_kinds": ["opening_delay", "camera_position_target", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(1628, 1633)},
        "message_text_required": True,
    },
    # end lane ch2a
    # lane ch2b
    "story026": {
        # 日沒灣: track-8 court theme, the ship deck framed, 雷特 / 雪拉 banter, 海輝魔 039 and
        # 甲殼蜂 038 close in by displacement walks, 雷歐納德's quip, dead messages, title,
        # win / fail / event statuses, then actPlayLevelMusic (track 12).
        "first_kind": "music_track",
        "min_events": 42,
        "required_kinds": ["music_track", "camera_position_set", "opening_delay", "dialogue_message_id", "actor_walk_disp", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "opening_music"],
        "required_message_ids": {str(i) for i in range(2423, 2428)},
        "message_text_required": True,
    },
    "story028": {
        # 眾神的宮殿遺址: actPlayLevelMusic (track 13) first, the camera scrolls up the hall, nine
        # Enemy050 appear in white light (story-object + object inserts, ids 5000-5003), the
        # party's four lines, dead messages, title, fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 86,
        "required_kinds": ["opening_music", "camera_position_set", "opening_delay", "dialogue_message_id", "camera_position_target_speed", "camera_position_target", "story_object_insert", "object_insert", "inserted_object_id_change", "inserted_object_wait_round", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2468, 2473)},
        "message_text_required": True,
    },
    "story029": {
        # 約瑟河: actPlayLevelMusic (track 16), the party walks in from the north, the captain 024
        # and two soldiers 023 talk with 雷歐納德 (renamed 梅爾 / 凱文, ids 1000 / 1001), title,
        # win / fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 82,
        "required_kinds": ["opening_music", "opening_delay", "actor_walk", "actor_action_wait", "dialogue_message_id", "actor_walk_wait", "player_name_set", "dead_message_registration", "player_id_change", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"380"} | {str(i) for i in range(1655, 1659)} | {"1660", "1661"} | {str(i) for i in range(1663, 1684)},
        "message_text_required": True,
    },
    "story030": {
        # 絕望之谷: actPlayLevelMusic (track 14), the party walks in from the east, 克羅蒂 053 and
        # the 049 riders from the west, the long confrontation, 053 set undead, title, statuses.
        "first_kind": "opening_music",
        "min_events": 97,
        "required_kinds": ["opening_music", "opening_delay", "camera_position_target", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "player_undead_flag", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"380"} | {"1017"} | {str(i) for i in range(1837, 1866)},
        "message_text_required": True,
    },
    "story031": {
        # 漆黑之森: track-9 opening, the four-way talk with one narration line, actPlayLevelMusic
        # (track 13), 傲 055 and the 049 riders come up, the north-edge escape row markers,
        # title, event / fail statuses.
        "first_kind": "music_track",
        "min_events": 76,
        "required_kinds": ["music_track", "opening_delay", "camera_object_target", "dialogue_message_id", "opening_music", "actor_walk_disp", "actor_walk_disp_wait", "dead_message_registration", "player_undead_flag", "section_title_resource", "show_position_marker", "camera_position_target", "event_status_enable", "fail_status_enable", "winfail_board_refresh", "show_position_marker_clear"],
        "required_message_ids": {"380"} | {str(i) for i in range(1900, 1924)},
        "message_text_required": True,
    },
    "story032": {
        # 拉格納沼地: actPlayLevelMusic (track 19), 雷歐納德's group walks in from the north, the
        # Wosfita force from the west with its taunts, title, fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 80,
        "required_kinds": ["opening_music", "opening_delay", "camera_position_target", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "camera_position_target_speed", "camera_object_target", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(1977, 1989)},
        "message_text_required": True,
    },
    "story033": {
        # 黃昏之丘 陰: track-8 opening, 緹娜's group walks in, their talk, actPlayLevelMusic (track
        # 18), 席德爾 056 and the undead walk up, the exchange, 056 set undead, south-edge escape
        # markers, title, statuses.
        "first_kind": "music_track",
        "min_events": 115,
        "required_kinds": ["music_track", "opening_delay", "camera_position_target", "actor_walk", "actor_walk_wait", "dialogue_message_id", "opening_music", "dead_message_registration", "player_undead_flag", "section_title_resource", "fail_status_enable", "event_status_enable", "show_position_marker", "winfail_board_refresh", "show_position_marker_clear"],
        "required_message_ids": {"380"} | {"728"} | {str(i) for i in range(1943, 1973)},
        "message_text_required": True,
    },
    "story034": {
        # 沙羅尼亞近郊: track-9 opening, 緹娜's group walks in from the west, the villagers 062 flee
        # at scripted speed, 036 / 037 / 038 pour in, three lines, title, statuses, then
        # actPlayLevelMusic (track 17).
        "first_kind": "music_track",
        "min_events": 78,
        "required_kinds": ["music_track", "opening_delay", "camera_position_target", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "camera_position_target_speed", "actor_walk", "actor_walk_wait", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "opening_music"],
        "required_message_ids": {"380"} | {str(i) for i in range(1997, 2007)},
        "message_text_required": True,
    },
    # end lane ch2b
    # lane ch2c: chapter-2 battle openings 36-45 (previews stop at first control).
    "story036": {
        # 薩魯司海岸: track 9, the party walks up from the south edge, 漢克斯 rounds on 雷歐納德, the camera jumps to the far shore where 傲 055 and the dark knights walk in, title and statuses.
        "first_kind": "music_track",
        "min_events": 80,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_walk_disp_wait", "dialogue_message_id", "camera_position_target", "player_undead_flag", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "opening_music"],
        "required_message_ids": {str(i) for i in range(2056, 2070)} | {"380", "1128"},
        "message_text_required": True,
    },
    "story037": {
        # 古代神殿遺跡: track 9, the party walks north, 克羅蒂 names the temple, the level music starts, 033 / 035 walk in under camera jumps, five random-position slots each get a 白光 flash, a statue delete and the 067 / 066 guardians, undead flags, three lines, title and statuses.
        "first_kind": "music_track",
        "min_events": 140,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_walk_disp_wait", "dialogue_message_id", "dialogue_message_if_exist", "opening_music", "camera_position_target", "random_position_set", "camera_random_position_target", "story_object_insert_random_position", "random_position_object_delete", "object_insert_random_position", "player_undead_flag", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"2088", "2089", "2090", "2091", "2093", "2094", "2095"},
        "message_text_required": True,
    },
    "story038": {
        # 幽闇墳場: level music first, the party walks north and waits on 雷歐納德, four lines, the 033 / 035 / 034 undead close in from three edges, 克羅蒂 points at the tomb, title, three escape markers, statuses, marker clear.
        "first_kind": "opening_music",
        "min_events": 130,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "show_position_marker", "camera_position_target", "fail_status_enable", "event_status_enable", "winfail_board_refresh", "show_position_marker_clear"],
        "required_message_ids": {str(i) for i in range(2479, 2485)},
        "message_text_required": True,
    },
    "story039": {
        # 黃昏之丘 陽: level music, the party walks up the hill, a slow scroll to the dark knights, two lines and a conditional third, title and statuses.
        "first_kind": "opening_music",
        "min_events": 42,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_walk_disp_wait", "camera_position_target_speed", "dialogue_message_id", "dialogue_message_if_exist", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"2130", "2131"},
        "message_text_required": True,
    },
    "story040": {
        # 聖靈之森: level music, the party walks in from the west edge, 傲 055 returns and argues with 克羅蒂 and 雷歐納德, title, win / fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 45,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2144, 2149)},
        "message_text_required": True,
    },
    "story041": {
        # 悲嘆之湖: track 9, the party walks north to the lake, 雷歐納德 tells the lake's story, 琥 spots the enemy, the level music starts, 049 / 065 / 席德爾 056 arrive, the brothers' exchange, title and statuses.
        "first_kind": "music_track",
        "min_events": 115,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "opening_music", "actor_walk_disp_wait", "actor_walk", "actor_walk_wait", "player_undead_flag", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2155, 2177)} | {"380", "1017"},
        "message_text_required": True,
    },
    "story043": {
        # 大地的裂縫: level music, the party walks to the ledge, four lines, a slow scroll to the sword, 037 / 038 / 051 close in, two lines, title and statuses.
        "first_kind": "opening_music",
        "min_events": 88,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk", "actor_action_wait", "dialogue_message_id", "camera_position_target_speed", "actor_walk_disp", "actor_walk_disp_wait", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2554, 2561)} | {"380"},
        "message_text_required": True,
    },
    "story044": {
        # 亞修頓大橋: level music, a slow scroll down the bridge, the party walks onto it, two lines, title and statuses.
        "first_kind": "opening_music",
        "min_events": 40,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {"2248", "2249"},
        "message_text_required": True,
    },
    "story045": {
        # 克萊恩城: level music, a slow scroll to the gate, 雷歐納德's one line, title, thirteen event statuses, four escape markers, statuses, marker clear.
        "first_kind": "opening_music",
        "min_events": 38,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "show_position_marker", "camera_position_target", "winfail_board_refresh", "show_position_marker_clear"],
        "required_message_ids": {"2265"},
        "message_text_required": True,
    },
    # end lane ch2c
    "story010": {
        # 帕尼西亞城 廢墟: track-8 court theme, 雷歐納德 and 緹娜 talk under the ruins, the
        # rain controller objects are inserted, the camera scrolls to the tree, lightning
        # flashes with fire bombs, the tree is replaced by its burning stand-in, the 034 /
        # 035 creatures close in, title and win／fail board.
        "first_kind": "music_track",
        "min_events": 85,
        "required_kinds": [
            "opening_music",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "story_object_insert",
            "sound_effect",
            "camera_position_target",
            "position_object_delete",
            "section_title_resource",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
        ],
        "required_message_ids": {"1081", "1082", "1083", "1084", "1085", "1086", "1087", "1088", "1089", "1090", "1091", "1092", "1093", "380", "873", "797", "1002"},
        "message_text_required": True,
    },
    "story008": {
        # 菲納斯河畔 (story-only): the party arrives at the Lars border, the exchange,
        # everyone walks on west, the script rewrites big-map points 8 / 9 and returns
        # to the big map.
        "first_kind": "camera_position_target",
        "min_events": 38,
        "end_kind": "scene_end_marker",
        "required_kinds": [
            "music_track",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "bigmap_point_event",
            "bigmap_point_encounter_ratio",
            "next_level_event",
        ],
        "required_message_ids": {str(i) for i in range(1052, 1057)} | {"380"},
        "message_text_required": True,
    },
    "story009": {
        # 廢都 曼多利亞 (story-only): villagers wander, the camera scrolls south at a
        # scripted speed, the party walks in with the walk sound on, 緹娜 is revealed
        # as the princess, point 9 turns back into a town and the script chains to
        # level 65.
        "first_kind": "camera_position_target",
        "min_events": 40,
        "end_kind": "scene_end_marker",
        "required_kinds": [
            "music_track",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "walk_sound_mode",
            "camera_position_target_speed",
            "dialogue_message_id",
            "bigmap_point_event",
            "next_level_event",
        ],
        "required_message_ids": {str(i) for i in range(1057, 1061)} | {"380"},
        "message_text_required": True,
    },
    "story065": {
        # 廢都 interior (story-only, chained from STORY009): 緹娜's plea to the
        # villagers, their refusal, the party leaving one by one, 雷歐納德's last word.
        "first_kind": "music_track",
        "min_events": 43,
        "end_kind": "scene_end_marker",
        "required_kinds": [
            "opening_delay",
            "actor_walk_wait",
            "actor_walk_and_delete",
            "dialogue_message_id",
            "next_level_event",
        ],
        "required_message_ids": {str(i) for i in range(1061, 1076)} | {"380"},
        "message_text_required": True,
    },
    # lane ch2a
    "story066": {
        # Camp after 廢都 (story-only, STORY065 -> 9,66): track 8, the party sits in silence, 雪拉 and 雷歐納德 walk
        # over, 緹娜 asks to see 帕尼西雅城; back to the big map at point 9.
        "first_kind": "music_track",
        "min_events": 22,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_wait", "next_level_event"],
        "required_message_ids": {str(i) for i in range(1076, 1081)} | {"380", "792"},
        "message_text_required": True,
    },
    "story067": {
        # Camp after 艾瓦台地 (story-only, winfail017 -> 17,67): track 8, 克里夫 064 steps up, 雷歐納德 demands the
        # pass, 雪拉 coaxes it out of him (actGetItem 281), then 嚎 questions 雷歐納德; back to the big map at point 17.
        "first_kind": "music_track",
        "min_events": 70,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "actor_walk_disp_wait", "dialogue_message_id", "actor_walk_wait", "item_grant", "next_level_event"],
        "required_message_ids": {str(i) for i in range(1379, 1412)} | {"380", "774", "821", "983"},
        "message_text_required": True,
    },
    "story068": {
        # Camp after the level-902 variant of 艾瓦台地 (story-only, winfail902 -> 17,68): track 8, only the 嚎 /
        # 雷歐納德 exchange of STORY067; back to the big map at point 17.
        "first_kind": "music_track",
        "min_events": 26,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "next_level_event"],
        "required_message_ids": {str(i) for i in range(1401, 1411)} | {"380", "821", "983"},
        "message_text_required": True,
    },
    "story069": {
        # Camp after 利魯瑪山地 (story-only, winfail019 / winfail904 -> 19,69): track 8, 雷特 lays out 那可那魯's
        # designs, 嚎 adds 冀羅's, 雷歐納德 walks over and asks everyone to choose, all seven stay; the script hides
        # track 18 and returns to the big map at point 19.
        "first_kind": "music_track",
        "min_events": 121,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_wait", "bigmap_track_flag_set", "next_level_event"],
        "required_message_ids": {str(i) for i in range(1488, 1548)} | {"380", "794", "873", "1017", "1024"},
        "message_text_required": True,
    },
    # end lane ch2a
    "story055": {
        # Camp at dusk after 戈爾山道 (story-only, winfail002 -> 2,55): track 8, 緹娜 reveals
        # she is the Lars princess and asks for help, 琥 walks off in refusal, 雷歐納德
        # sends her to rest; chains to level 56.
        "first_kind": "music_track",
        "min_events": 44,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_wait", "next_level_event"],
        "required_message_ids": {str(i) for i in range(791, 819)} | {"380"},
        "message_text_required": True,
    },
    "story056": {
        # Camp in the morning (story-only, chained from STORY055): 緹娜 is inserted by
        # obj_Story_Player2, the party agrees to her wager and walks off west; the
        # script hides track 3 and returns to the big map at point 2.
        "first_kind": "music_track",
        "min_events": 26,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "story_object_insert", "actor_walk_wait", "dialogue_message_id",
                           "actor_walk_and_delete", "actor_walk_and_delete_wait", "bigmap_track_flag_set", "next_level_event"],
        "required_message_ids": {str(i) for i in range(819, 828)} | {"790"},
        "message_text_required": True,
    },
    "story061": {
        # Camp after 盜賊洞窟 (story-only, winfail003 -> 61,61): 漢克斯 walks in and reports,
        # 緹娜 makes him drop the royal address, 雷歐納德 and 琥 comment; the script reveals
        # track 3 / point 2, arms 歐姆村 event 10 and returns to the big map at point 3.
        "first_kind": "music_track",
        "min_events": 27,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "actor_walk_wait", "dialogue_message_id", "bigmap_track_flag_clear",
                           "bigmap_show_track_point", "town_exec_event", "next_level_event"],
        "required_message_ids": {str(i) for i in range(847, 858)} | {"380"},
        "message_text_required": True,
    },
    "story062": {
        # Camp after 席達鎮 (story-only, winfail006 -> 6,62): 緹娜 questions 雷歐納德's motives
        # and goes to sleep (walk-and-delete), 漢克斯 walks in with his warning; chains to
        # level 63.
        "first_kind": "music_track",
        "min_events": 27,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_and_delete_wait", "actor_walk_wait",
                           "actor_walk", "next_level_event"],
        "required_message_ids": {str(i) for i in range(980, 992)} | {"380"},
        "message_text_required": True,
    },
    "story063": {
        # Throne hall (story-only, chained from STORY062): the spies report to 克里歐司
        # through actShapeMessage portraits, the attendants leave, the king muses alone
        # (布來特); the script clears the hidden flag of track 6 and returns to the big map.
        "first_kind": "music_track",
        "min_events": 36,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "actor_walk_and_delete_wait", "actor_walk_and_delete",
                           "shape_message", "actor_walk_disp_wait", "bigmap_track_flag_clear", "next_level_event"],
        "required_message_ids": {"993", "994", "678", "995", "996", "999", "1001", "1003", "1004", "1005", "1006", "380"},
        "message_text_required": True,
    },
    "story064": {
        # Camp after 寧靜之森 (story-only, winfail007 -> 7,64): 雪拉 asks to travel with the
        # party and is accepted; dialogue only, then back to the big map at point 7.
        "first_kind": "music_track",
        "min_events": 30,
        "end_kind": "scene_end_marker",
        "required_kinds": ["opening_delay", "dialogue_message_id", "next_level_event"],
        "required_message_ids": {str(i) for i in range(1036, 1052)} | {"718", "380"},
        "message_text_required": True,
    },
    # lane ch3
    "story073": {
        # 悲嘆之湖 aftermath (winfail041 -> 41,73, on the level-41 map): track 9, the beaten 席德爾
        # asks 雷特 to kill him, 雷歐納德 leaves the choice to 雷特, and the script ends on
        # actSelectInsertEvent (kill / spare) — the winfail073 event chains are compiled separately
        # (story scene select_event_timelines); there is no battle body.
        "first_kind": "music_track",
        "min_events": 12,
        "required_kinds": ["opening_delay", "dialogue_message_id", "event_select_insert"],
        "required_message_ids": {"2182", "2183", "380", "2184"},
        "message_text_required": True,
    },
    "story075": {
        # 自覺與宿命 (winfail045 -> 75,75, on the level-57 hall): level music, a slow scroll down the hall, the nine-slot party walks up 192px, 塔克斯 054 and 克羅蒂 argue (2269-2279), title, win / fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 60,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "player_undead_flag", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "winfail_board_refresh", "win_status_enable", "event_status_enable"],
        "required_message_ids": {str(i) for i in range(2269, 2280)},
        "message_text_required": True,
    },
    "story076": {
        # 最終的序曲 (final 76, the LEVEL58 throne hall): level music, a slow scroll, the party walks up 224px, 雷歐納德 / 克羅蒂 confront the elf king 058 (2291-2298 + 380), title, win / fail and eleven event statuses.
        "first_kind": "opening_music",
        "min_events": 60,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "player_undead_flag", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "winfail_board_refresh", "win_status_enable", "event_status_enable"],
        "required_message_ids": {str(i) for i in range(2291, 2299)} | {"380"},
        "message_text_required": True,
    },
    "story077": {
        # 破滅的命運 (final 77): level music, slow scroll, the party walks up, the camera jumps to 席德爾 056, LASERUP001 and a 白光 flash delete the dead elf king stand object, the evolution exchange (2350-2360 + 804), title, fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 65,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "player_undead_flag", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "winfail_board_refresh", "camera_object_target", "sound_effect", "story_object_insert", "position_object_delete", "event_status_enable"],
        "required_message_ids": {str(i) for i in range(2350, 2361)} | {"804"},
        "message_text_required": True,
    },
    "story078": {
        # 接觸 (final 78): level music, slow scroll, the party walks up (咕嚕's token binds to nothing), the 76 exchange again (2291-2298 + 380), title, fail and three event statuses.
        "first_kind": "opening_music",
        "min_events": 55,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "player_undead_flag", "actor_walk_disp", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "winfail_board_refresh", "event_status_enable"],
        "required_message_ids": {str(i) for i in range(2291, 2299)} | {"380"},
        "message_text_required": True,
    },
    "story079": {
        # 終焉 (winfail078 event 2 -> 79,79): level music, slow scroll, 咕嚕最終型態 057 revealed (2383-2391 + 2326), three SHOOT008 白光 shots and a BOMB0009 白光2 burst delete the elf king, 雪拉's cry, title, win / fail statuses.
        "first_kind": "opening_music",
        "min_events": 50,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "player_undead_flag", "dialogue_message_id", "camera_position_target", "sound_effect", "story_object_insert", "actor_delete", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2383, 2392)} | {"2326"},
        "message_text_required": True,
    },
    "story080": {
        # 禁忌之魂 (winfail038 -> 80,80): level music, the nine slots walk in from the west edge to fixed cells, 緹娜 / 克羅蒂 / 雷歐納德 on the sealed dark things (2486-2492), title, fail and four event statuses.
        "first_kind": "opening_music",
        "min_events": 50,
        "required_kinds": ["camera_position_set", "opening_delay", "actor_walk", "actor_action_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2486, 2493)},
        "message_text_required": True,
    },
    "story059": {
        # 劫數 (STORY081 -> 59,59): level music, two slow scrolls, the party walks to fixed cells, 雷歐納德 strikes the statue (EFF0013, 白光) and is thrown back, four faceless actShapeMessage voices, the 白光2 burst inserts Enemy060 and the 弱點, the statue stand object is deleted, title, win / fail / event statuses.
        "first_kind": "opening_music",
        "min_events": 75,
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "actor_walk", "actor_walk_wait", "dialogue_message_id", "sound_effect", "story_object_insert", "shape_message", "camera_position_target", "object_insert", "position_object_delete", "player_undead_flag", "dead_message_registration", "section_title_resource", "win_status_enable", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(2333, 2347)} - {"2339", "2341", "2343", "2345"},
        "message_text_required": True,
    },
    "story057": {
        # 自覺與宿命・塔克斯之死 (story-only, winfail075 -> 57,57): track 10, the dying 塔克斯 054 and 克羅蒂 (2285-2290), he vanishes, storage window / keep ST / actSetNextPlayLevelGetOverEvent 0 recorded.
        "first_kind": "music_track",
        "min_events": 20,
        "end_kind": "scene_end_marker",
        "required_kinds": ["camera_position_set", "opening_delay", "dialogue_message_id", "actor_delete", "storage_window_enter", "player_stamina_keep", "next_level_get_over_event"],
        "required_message_ids": {str(i) for i in range(2285, 2291)},
        "message_text_required": True,
    },
    "story081": {
        # 妖精王的告白 (story-only, winfail076 -> 81,81): track 10, the elf king's confession to 雷歐納德 / 克羅蒂 / 雪拉 (2310-2332 + 2295 / 1852), he dies, storage window / keep ST, actSetNextPlayLevelEvent 59,59.
        "first_kind": "music_track",
        "min_events": 55,
        "end_kind": "scene_end_marker",
        "required_kinds": ["camera_position_set", "opening_delay", "dialogue_message_id", "actor_delete", "storage_window_enter", "player_stamina_keep", "next_level_event"],
        "required_message_ids": {str(i) for i in range(2310, 2333)} | {"2295", "1852"},
        "message_text_required": True,
    },
    "story082": {
        # 破滅的命運・終幕 (story-only, winfail077 -> 82,82): track 4, 毀滅天使 059's last words (2369-2371), he vanishes, 雷特 and 雪拉 step forward, the party's farewell (2372-2378 + 380), actSetNextPlayLevelEvent 90,998 (game clear).
        "first_kind": "music_track",
        "min_events": 30,
        "end_kind": "scene_end_marker",
        "required_kinds": ["camera_position_set", "opening_delay", "dialogue_message_id", "actor_delete", "actor_walk_disp_wait", "next_level_event"],
        "required_message_ids": {str(i) for i in range(2369, 2379)} | {"380"},
        "message_text_required": True,
    },
    # end lane ch3
    "story900": {
        # lane parent-900: 曼多力亞 confrontation — the court theme, the five-member
        # party walks in from the south edge while the Wosfita soldiers press the
        # villagers, dead messages are registered, the camera scrolls to the square and
        # the scene ends on actSelectInsertEvent (kick the soldiers / fight): the winfail
        # event chains are compiled separately (story scene select_event_timelines).
        "first_kind": "background_object_target",
        "min_events": 40,
        "required_kinds": [
            "music_track",
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "dead_message_registration",
            "camera_position_target_speed",
            "event_select_insert",
        ],
        "required_message_ids": {"1103", "1104", "1105", "1106", "1107", "1108", "1109", "1110", "1111", "1112"},
        "message_text_required": True,
    },
    "story901": {
        # 菲納斯河畔伏擊 (the ambush winfail010 arms on big-map point 8, fought on the level 8
        # riverside map): the level music starts, the five-member party walks in from the
        # north edge, the Wosfita captain 024 calls out the traitor 雷歐納德 and he answers,
        # WORD901 title, fail status and events 0 / 1 (annihilation / round-8 reinforcements)
        # are armed before first control.
        "first_kind": "opening_music",
        "min_events": 22,
        "required_kinds": [
            "opening_delay",
            "actor_walk",
            "actor_walk_wait",
            "dialogue_message_id",
            "section_title_resource",
            "fail_status_enable",
            "event_status_enable",
            "winfail_board_refresh",
            "opening_music",
        ],
        "required_message_ids": {"1139", "1140", "1141"},
        "message_text_required": True,
    },
    # lane alt902: side-route replacement battles 902 / 903 / 904 (opening previews).
    # story903 / story904 are aliases of story024 / story019 below the literal: 903 is level 24's
    # opening with 雷特's line 1629 added (the same 1628-1632 range and event kinds), 904 is STORY019
    # byte for byte.
    "story902": {
        # 艾瓦台地 variant (TOWNDEF 命運神殿 event 53 arms point 17 with 902 while unvisited; LEVEL17.SHP by
        # the obs 地圖管理員): level music, the camera frames the mine entrance, the five-member party walks
        # in from the east edge and finds the workers dead (1422-1426), five dead messages, the WORD902
        # 尋 / SEEK title, fail status and events 0-5 (the pass search) before first control.
        "first_kind": "opening_music",
        "min_events": 38,
        "required_kinds": ["opening_delay", "camera_position_target", "actor_walk", "actor_walk_wait", "dialogue_message_id", "dead_message_registration", "section_title_resource", "fail_status_enable", "event_status_enable", "winfail_board_refresh"],
        "required_message_ids": {str(i) for i in range(1422, 1427)},
        "message_text_required": True,
    },
    # end lane alt902
    # lane ch2b
    "story070": {
        # Camp before 克萊恩城 (story-only, winfail029 -> 29,70): track 9, 雷歐納德 and 緹娜 talk
        # about fear and truth; back to the big map at point 29.
        "first_kind": "music_track",
        "min_events": 27,
        "end_kind": "scene_end_marker",
        "required_kinds": ["music_track", "opening_delay", "dialogue_message_id", "next_level_event"],
        "required_message_ids": {"380"} | {"718"} | {str(i) for i in range(1691, 1701)},
        "message_text_required": True,
    },
    "story071": {
        # Throne hall (story-only, winfail031 -> 31,71): track 8, camera set then scrolled at speed,
        # 克里歐司 muses, 克羅蒂 walks in and questions him; ends on big-map writes (point 33 /
        # track 32 shown, 琥 walks 30 -> 33) without a next-level token.
        "first_kind": "music_track",
        "min_events": 33,
        "end_kind": "scene_end_marker",
        "required_kinds": ["music_track", "camera_position_set", "opening_delay", "camera_position_target_speed", "dialogue_message_id", "actor_walk_wait", "bigmap_point_flag_clear", "bigmap_track_flag_clear", "bigmap_show_track_point", "bigmap_walker_player_id", "bigmap_walk_to_point"],
        "required_message_ids": {"380"} | {str(i) for i in range(1927, 1937)},
        "message_text_required": True,
    },
    "story072": {
        # 沙羅尼亞 promenade (story-only, town event 167 -> 35,72): track 10, 雷歐納德 and 緹娜 walk
        # in, his confession, 瑪哈亞鎮 event 92 added, back to the big map at point 35.
        "first_kind": "music_track",
        "min_events": 45,
        "end_kind": "scene_end_marker",
        "required_kinds": ["music_track", "camera_position_set", "opening_delay", "actor_walk", "actor_walk_wait", "dialogue_message_id", "town_event_add", "next_level_event"],
        "required_message_ids": {"380"} | {"718"} | {"728"} | {"873"} | {str(i) for i in range(2041, 2055)},
        "message_text_required": True,
    },
    # end lane ch2b
    # lane ch2c
    "story074": {
        # 斐達克旅館 (story-only, TOWNDEF event 178 -> 42,74): track 9, a slow scroll into the inn, 雷歐納德 steps forward and everyone states their resolve before Klein (雪拉 reveals the elf king is her father); the script rewrites the 斐達克 / 薛維斯港 tavern events, reveals track 42 / point 44 and returns to the big map at point 42.
        "first_kind": "music_track",
        "min_events": 80,
        "end_kind": "scene_end_marker",
        "required_kinds": ["camera_position_set", "opening_delay", "camera_position_target_speed", "actor_walk_disp_wait", "dialogue_message_id", "town_event_delete", "town_event_add", "bigmap_track_flag_clear", "bigmap_point_flag_clear", "next_level_event"],
        "required_message_ids": {str(i) for i in range(2216, 2248)} | {"380", "1065", "1465"},
        "message_text_required": True,
    },
    # end lane ch2c
}
# lane alt902: the side-route variants replay their base level's opening — 903 (哈莫特沙漠, winfail021's
# 24,903,0) is STORY024 plus 雷特's line 1629 inside the same 1628-1632 range; 904 (利魯瑪山地, winfail902's
# 19,904,0) is STORY019 byte for byte — so their profiles are the base profiles.
PROFILES["story903"] = PROFILES["story024"]
PROFILES["story904"] = PROFILES["story019"]
# Random-encounter levels 501-578 share one opening shape (tools/hsltools/legacy.py ENCOUNTER_RANGE):
# the base level's default music, a 40-tick delay, 雷歐納德's dead message 741, win / fail status 0
# and the board refresh before first control — no walks, dialogue or section title.
ENCOUNTER_PROFILE: dict[str, Any] = {
    "first_kind": "default_level_music",
    "min_events": 7,
    "required_kinds": ["opening_delay", "dead_message_registration", "win_status_enable", "fail_status_enable", "winfail_board_refresh"],
    "required_message_ids": set(),
    "message_text_required": True,
}
for _encounter_level in range(501, 579):
    PROFILES.setdefault(f"story{_encounter_level}", ENCOUNTER_PROFILE)
# end lane alt902


def _fail(message: str) -> None:
    raise SystemExit(f"opening timeline check failed: {message}")


def check_opening_timeline(path: Path, expected_source_script: str | None = None) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        timeline: dict[str, Any] = json.load(handle)

    if timeline.get("schema") != SCHEMA:
        _fail("unexpected schema")
    source_script = str(timeline.get("source_script", ""))
    if expected_source_script is not None and source_script != expected_source_script:
        _fail(f"source_script must be {expected_source_script}")
    profile = PROFILES.get(source_script)
    if profile is None:
        _fail(f"no check profile for source_script {source_script!r}")
    if timeline.get("evidence_tier") != "resource-derived":
        _fail("timeline evidence_tier must be resource-derived")

    events = timeline.get("events")
    if not isinstance(events, list) or len(events) < int(profile["min_events"]):
        _fail(f"timeline must include {source_script} opening events")
    if int(timeline.get("event_count", 0)) != len(events):
        _fail("event_count mismatch")

    ids: set[str] = set()
    kinds: list[str] = []
    message_ids: set[str] = set()
    for event in events:
        if not isinstance(event, dict):
            _fail("event must be an object")
        event_id = _require_string(event, "id")
        if event_id in ids:
            _fail(f"duplicate event id {event_id}")
        ids.add(event_id)
        kind = _require_string(event, "kind")
        kinds.append(kind)
        _require_string(event, "source_token")
        _require_string(event, "display_line")
        _require_string(event, "evidence_tier")
        if not isinstance(event.get("args"), list):
            _fail(f"{event_id} args must be a list")
        if kind == "dialogue_message_id":
            message_ids.add(_require_string(event, "message_id"))
            if profile["message_text_required"]:
                _require_string(event, "message_text")
                if not event.get("narration", False):
                    _require_string(event, "speaker_name")
        if kind == "script_action":
            _fail(f"{event_id} keeps an unclassified script action {event.get('script_action_name')!r}")
        if not event.get("synthetic", False) and event.get("source_script") != source_script:
            _fail(f"{event_id} source_script differs from the timeline source")
        unresolved = event.get("unresolved_semantics")
        if not isinstance(unresolved, list) or not unresolved:
            _fail(f"{event_id} must keep unresolved semantics")

    if kinds[0] != profile["first_kind"]:
        _fail(f"first event must be {profile['first_kind']}")
    end_kind = str(profile.get("end_kind", "first_control_marker"))
    if kinds[-1] != end_kind:
        _fail(f"last event must be {end_kind}")
    if not events[-1].get("synthetic", False):
        _fail(f"{end_kind} must stay synthetic")
    for required_kind in profile["required_kinds"]:
        if required_kind not in kinds:
            _fail(f"missing required kind {required_kind}")
    for required_message in sorted(profile["required_message_ids"]):
        if required_message not in message_ids:
            _fail(f"missing opening message id {required_message}")

    contract = timeline.get("contract")
    if not isinstance(contract, dict):
        _fail("contract missing")
    not_proven = contract.get("not_proven", [])
    if "original message box layout" not in not_proven or "camera curve" not in not_proven:
        _fail("contract must keep dialogue/camera gaps explicit")

    return {"source_script": source_script, "event_count": len(events), "message_count": len(message_ids)}


def _require_string(parent: dict[str, Any], key: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value:
        _fail(f"missing string {key}")
    return value


def _level_tag(level: int) -> str:
    return f'{level:03d}'


class OpeningTimelineCompileTask(GeneratedFilesTask):
    """render = compile_opening_timeline(story, message_evidence) as the tracked manifest bytes.
    for_level(level) uses the level's seed / message evidence / manifest; for_chapter() is the
    chapter-wide manifest compiled from the story051 script IR without message evidence
    (content/imported/hsl/chapter01/opening_timeline.json, used by the development trials);
    the module command line constructs one from explicit paths (level None, nothing replaced)."""
    family = 'opening_timeline_compile'

    def __init__(self, level: int | None, story: Path, output: Path, message_evidence: Path | None, chapter: bool = False) -> None:
        self.level = level
        self.story, self.output, self.message_evidence = story, output, message_evidence
        self.name = f'opening_timeline_compile:{CHAPTER_SHARED if chapter else level if level is not None else output.as_posix()}'
        self.inputs = tuple(path.as_posix() for path in (story, message_evidence) if path is not None)
        self.outputs = (output.as_posix(),)
        self.scripts = ('tools/hsltools/levels/timeline.py',)
        if chapter:
            self.replaces = ('tools/hsl_opening_timeline_compile.py --check',)
        elif level is None:
            self.replaces = ()
        else:
            self.replaces = (f'tools/hsl_opening_timeline_compile.py {story.as_posix()} --message-evidence {message_evidence.as_posix()}'
                             f' --output {output.as_posix()} --check',)

    @classmethod
    def for_chapter(cls) -> 'OpeningTimelineCompileTask':
        return cls(None, DEFAULT_STORY, DEFAULT_OUTPUT, None, chapter=True)

    @classmethod
    def for_level(cls, level: int) -> 'OpeningTimelineCompileTask':
        tag = _level_tag(level)
        return cls(level, Path(f'content/generated/hsl/chapter01/battle{tag}_seed.json'),
                   Path(f'content/imported/hsl/chapter01/battle{tag}/opening_timeline.json'),
                   Path(f'content/imported/hsl/chapter01/battle{tag}/message_text_evidence.json'))

    def render(self, ctx: Context) -> dict[str, bytes]:
        with legacy_failures(self.name):
            report = compile_opening_timeline(self.story, self.message_evidence)
        return {self.output.as_posix(): encode_json(report)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        report = json.loads(next(iter(rendered.values())))
        if mode == 'check':
            return f"OPENING_TIMELINE_CHECK_PASS source={report['source_script']} events={report['event_count']} output={self.output}"
        return f"opening timeline wrote {self.output} events={report['event_count']}"


class OpeningTimelineCheckTask(Task):
    """The profile checker over a tracked manifest; no regeneration path (compile owns that)."""
    family = 'opening_timeline_check'

    def __init__(self, level: int | None, timeline: Path, expected_source_script: str | None, chapter: bool = False) -> None:
        self.level = level
        self.timeline, self.expected_source_script = timeline, expected_source_script
        self.name = f'opening_timeline_check:{CHAPTER_SHARED if chapter else level if level is not None else timeline.as_posix()}'
        self.inputs = (timeline.as_posix(),)
        self.outputs = (timeline.as_posix(),)
        self.scripts = ('tools/hsltools/levels/timeline.py',)
        if chapter:
            self.replaces = ('tools/hsl_opening_timeline_check.py',)
        elif level is None:
            self.replaces = ()
        else:
            self.replaces = (f'tools/hsl_opening_timeline_check.py {timeline.as_posix()} --source-script {expected_source_script}',)

    @classmethod
    def for_chapter(cls) -> 'OpeningTimelineCheckTask':
        return cls(None, DEFAULT_TIMELINE, 'story051', chapter=True)

    @classmethod
    def for_level(cls, level: int) -> 'OpeningTimelineCheckTask':
        tag = _level_tag(level)
        return cls(level, Path(f'content/imported/hsl/chapter01/battle{tag}/opening_timeline.json'), f'story{tag}')

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            summary = check_opening_timeline(self.timeline, self.expected_source_script)
        return (f"opening timeline ok: source={summary['source_script']} events={summary['event_count']} "
                f"messages={summary['message_count']} timeline={self.timeline}")

    def generate(self, ctx: Context) -> str:
        raise NoRegenerationPath(f'{self.name}: pure checker; regenerate the manifest with opening_timeline_compile')


def tasks() -> list[Task]:
    levels = imported_levels()
    return [OpeningTimelineCompileTask.for_chapter(), *(OpeningTimelineCompileTask.for_level(level) for level in levels),
            OpeningTimelineCheckTask.for_chapter(), *(OpeningTimelineCheckTask.for_level(level) for level in levels)]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("timeline", nargs="?", type=Path, default=DEFAULT_TIMELINE)
    parser.add_argument("--source-script", default=None, help="required source_script (default: story051 for the default timeline)")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    expected = args.source_script
    if expected is None and args.timeline == DEFAULT_TIMELINE:
        expected = "story051"
    try:
        print(OpeningTimelineCheckTask(None, args.timeline, expected).check(Context()))
    except CheckFailed as error:
        raise SystemExit(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
