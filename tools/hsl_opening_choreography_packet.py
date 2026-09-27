#!/usr/bin/env python3
"""Build the first-scene opening choreography evidence packet."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from hsltools.evidence import index as evidence_index


SCHEMA = "hsl_first_scene_opening_choreography_packet.v1"
DEFAULT_VISUAL_INDEX = Path("docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json")
DEFAULT_TIMELINE = Path("content/imported/hsl/chapter01/opening_timeline.json")
DEFAULT_MAP_OBJECTS = Path("content/imported/hsl/chapter01/map_objects.json")
DEFAULT_MAP_OBJECT_VISIBILITY = Path("content/imported/hsl/chapter01/map_object_visibility_evidence.json")
DEFAULT_ACTOR_WALK = Path("content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json")
DEFAULT_RUNTIME_CAPTURE = Path("ignored/first-scene-dev-interaction-harness/latest/manifest.json")
DEFAULT_OPENING_CAPTURE = Path("ignored/first-scene-opening-captures/latest/manifest.json")
DEFAULT_AUTOPLAY_CAPTURE = Path("ignored/first-scene-dev-opening-autoplay-harness/latest/manifest.json")
DEFAULT_OUTPUT = Path("docs/evidence_packets/runtime_observations/first_scene_opening_choreography_packet.json")
DEFAULT_MARKDOWN = Path("docs/evidence_packets/runtime_observations/first_scene_opening_choreography_packet.md")
MISSING_CAPTURE_STATUS = "missing_generated_capture"

REQUIRED_VISUAL_IDS = {
    "opening_transition_rain_frame",
    "opening_transition_castle_wall_frame",
    "opening_lower_formation_before_dialogue",
    "opening_dialogue_leonard",
    "opening_dialogue_map_only_gap",
    "opening_dialogue_soldier",
    "p1_route_upper_formation_11",
    "p1_route_upper_formation_12",
    "p1_route_action_menu_13",
    "first_control_action_menu",
}

DIRECT_OPENING_ACTOR_TOKENS = {"actWalkDispWait"}

ACTOR_TOKEN_TO_RUNTIME = {
    "SID_PLAYER0": {"unit_id": "leonard", "actor_id": "001", "role": "player_commanded"},
    "SID_ENEMY021": {"unit_id": "enemy021_1", "actor_id": "021", "role": "enemy_force"},
    "SID_ENEMY023": {"unit_id": "enemy023_1", "actor_id": "023", "role": "ai_controlled_ally"},
    "SID_ENEMY024": {"unit_id": "enemy024_1", "actor_id": "024", "role": "ai_controlled_ally"},
    "SID_ENEMY026": {"unit_id": "enemy026_1", "actor_id": "026", "role": "enemy_force"},
}

MISSING_ORIGINAL_TRUTH = [
    "first_control_idle_no_menu",
    "complete_enemy_gate_entry_paths",
    "complete_friendly_entry_paths",
    "continuous_camera_curve",
    "original_delay_time_scale",
    "dialogue_text_source",
    "actor_foot_anchor_and_path_timing",
]


def build_packet(args: argparse.Namespace) -> dict[str, Any]:
    visual_index = _load_json(args.visual_index)
    timeline = _load_json(args.timeline)
    map_objects = _load_json(args.map_objects)
    map_object_visibility = _load_json(args.map_object_visibility)
    actor_walk = _load_json(args.actor_walk)
    runtime_capture = _load_json_or_missing_capture(args.runtime_capture, "hsl_first_scene_runtime_capture.v1")
    opening_capture = _load_json_or_missing_capture(args.opening_capture, "hsl_first_scene_opening_capture.v1")
    autoplay_capture = _load_json_or_missing_capture(args.autoplay_capture, "hsl_first_scene_opening_autoplay_capture.v1")

    visual_by_id = {str(item.get("id", "")): item for item in visual_index.get("evidence", []) if isinstance(item, dict)}
    timeline_events = [item for item in timeline.get("events", []) if isinstance(item, dict)]
    direct_actor_events = [
        event for event in timeline_events
        if str(event.get("script_action_name", "")) in DIRECT_OPENING_ACTOR_TOKENS
    ]
    dialogue_events = [event for event in timeline_events if str(event.get("kind", "")) == "dialogue_message_id"]

    packet = {
        "schema": SCHEMA,
        "checked_date": "2026-09-01",
        "purpose": "Evidence-bounded opening choreography packet for BattleSceneRuntime and follow-on implementation.",
        "source_policy": (
            "Only local original-runtime promoted frames, STORY051 resource-derived action tokens, imported map-object evidence, "
            "actor walk manifest, and current Godot capture manifests are used. Superseded Godot captures, uncurated candidate frames, raw capture trees, "
            "and directory-level labels are not choreography truth."
        ),
        "evidence_tier": "mixed-runtime-measured-resource-derived-godot-rendered-provisional",
        "sources": _source_summary(
            args,
            visual_index,
            timeline,
            map_objects,
            map_object_visibility,
            actor_walk,
            runtime_capture,
            opening_capture,
            autoplay_capture,
        ),
        "visual_evidence": _visual_evidence_summary(visual_by_id),
        "script_timeline": _timeline_summary(args.timeline, timeline, direct_actor_events, dialogue_events),
        "actor_choreography": _actor_choreography_summary(direct_actor_events, dialogue_events, actor_walk),
        "choreography_segments": _choreography_segments(visual_by_id, direct_actor_events, dialogue_events, opening_capture, autoplay_capture),
        "current_godot_consumption": _current_godot_consumption(
            args.runtime_capture,
            args.opening_capture,
            args.autoplay_capture,
            runtime_capture,
            opening_capture,
            autoplay_capture,
        ),
        "missing_original_truth": MISSING_ORIGINAL_TRUTH,
        "forbidden_inferences": [
            "Do not infer enemy or allied entry paths from dialogue speaker tokens alone.",
            "Do not treat p1_route_upper_formation_11/12 as first-control idle truth.",
            "Do not treat opening_dialogue_map_only_gap as proof that player control has started.",
            "Do not treat the current Godot token overlay as original UI or original handler timing.",
            "Do not convert EVEF placement candidates or map-object anchors into final actor foot positions.",
        ],
        "next_implementation_gate": [
            "Consume direct STORY051 actor token only for Leonard's provisional motion unless another handler/source proves more paths.",
            "Before adding enemy/friendly entry paths, produce either static handler evidence or a promoted original-runtime frame sequence/contact sheet.",
            "Before declaring first-control formation truth, resolve first_control_idle_no_menu or equivalent narrow evidence.",
            "Before upgrading camera choreography, replace candidate anchors with a continuous camera curve or measured frame sequence.",
        ],
        "provisional": True,
    }
    return packet


def _source_summary(
    args: argparse.Namespace,
    visual_index: dict[str, Any],
    timeline: dict[str, Any],
    map_objects: dict[str, Any],
    map_object_visibility: dict[str, Any],
    actor_walk: dict[str, Any],
    runtime_capture: dict[str, Any],
    opening_capture: dict[str, Any],
    autoplay_capture: dict[str, Any],
) -> dict[str, Any]:
    return {
        "visual_index": _source_entry(args.visual_index, visual_index),
        "opening_timeline": _source_entry(args.timeline, timeline),
        "map_objects": _source_entry(args.map_objects, map_objects),
        "map_object_visibility": _source_entry(args.map_object_visibility, map_object_visibility),
        "actor_walk_manifest": _source_entry(args.actor_walk, actor_walk),
        "runtime_capture": _source_entry(args.runtime_capture, runtime_capture),
        "opening_capture": _source_entry(args.opening_capture, opening_capture),
        "opening_autoplay_capture": _source_entry(args.autoplay_capture, autoplay_capture),
    }


def _source_entry(path: Path, data: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": path.as_posix(),
        "schema": str(data.get("schema", "")),
        "evidence_tier": str(data.get("evidence_tier", "")),
        "capture_status": str(data.get("capture_status", "present")),
    }


def _visual_evidence_summary(visual_by_id: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    for evidence_id in sorted(REQUIRED_VISUAL_IDS):
        entry = visual_by_id.get(evidence_id, {})
        evidence.append(
            {
                "id": evidence_id,
                "file": str(entry.get("file", "")),
                "status": str(entry.get("status", "")),
                "evidence_tier": str(entry.get("evidence_tier", "")),
                "visual_state": str(entry.get("visual_state", "")),
                "use_for": entry.get("use_for", []),
                "not_for": entry.get("not_for", []),
            }
        )
    return evidence


def _timeline_summary(
    timeline_path: Path,
    timeline: dict[str, Any],
    direct_actor_events: list[dict[str, Any]],
    dialogue_events: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "schema": str(timeline.get("schema", "")),
        "path": timeline_path.as_posix(),
        "event_count": int(timeline.get("event_count", 0)),
        "direct_actor_motion_count": len(direct_actor_events),
        "direct_actor_motion_tokens": [
            {
                "id": str(event.get("id", "")),
                "actor_token": str(event.get("actor_token", "")),
                "source_token": str(event.get("source_token", "")),
                "args": event.get("args", []),
                "evidence_tier": str(event.get("evidence_tier", "")),
            }
            for event in direct_actor_events
        ],
        "dialogue_message_ids": [str(event.get("message_id", "")) for event in dialogue_events],
        "dialogue_actor_tokens": sorted({str(event.get("actor_token", "")) for event in dialogue_events if str(event.get("actor_token", ""))}),
        "contract_not_proven": timeline.get("contract", {}).get("not_proven", []),
    }


def _actor_choreography_summary(
    direct_actor_events: list[dict[str, Any]],
    dialogue_events: list[dict[str, Any]],
    actor_walk: dict[str, Any],
) -> list[dict[str, Any]]:
    direct_by_actor: dict[str, list[dict[str, Any]]] = {}
    for event in direct_actor_events:
        direct_by_actor.setdefault(str(event.get("actor_token", "")), []).append(event)
    dialogue_tokens = {str(event.get("actor_token", "")) for event in dialogue_events}
    actor_entries: list[dict[str, Any]] = []
    actor_manifest = actor_walk.get("actors", {})
    for actor_token, runtime in ACTOR_TOKEN_TO_RUNTIME.items():
        direct_events = direct_by_actor.get(actor_token, [])
        if direct_events:
            motion_status = "direct_story051_walk_token"
        elif actor_token in dialogue_tokens:
            motion_status = "dialogue_actor_only_no_direct_walk_token"
        else:
            motion_status = "known_first_scene_actor_no_story051_motion_token"
        actor_entries.append(
            {
                "actor_token": actor_token,
                "unit_id": runtime["unit_id"],
                "actor_id": runtime["actor_id"],
                "role": runtime["role"],
                "motion_status": motion_status,
                "direct_motion_tokens": [str(event.get("source_token", "")) for event in direct_events],
                "dialogue_message_ids": [
                    str(event.get("message_id", "")) for event in dialogue_events
                    if str(event.get("actor_token", "")) == actor_token
                ],
                "actor_walk_manifest_status": "present" if runtime["actor_id"] in actor_manifest else "missing",
                "evidence_tier": "resource-derived",
                "provisional": True,
            }
        )
    return actor_entries


def _choreography_segments(
    visual_by_id: dict[str, dict[str, Any]],
    direct_actor_events: list[dict[str, Any]],
    dialogue_events: list[dict[str, Any]],
    opening_capture: dict[str, Any],
    autoplay_capture: dict[str, Any],
) -> list[dict[str, Any]]:
    return [
        {
            "id": "transition_context",
            "claim": "Opening transition visual anchors exist, but they are not battlefield camera or actor path proof.",
            "original_runtime_evidence_ids": ["opening_transition_rain_frame", "opening_transition_castle_wall_frame"],
            "godot_capture_stages": ["opening_music", "opening_delay"],
            "implementation_status": "visual_anchor_only",
            "can_drive_runtime_motion": False,
            "not_proven": ["battlefield camera crop", "actor formation", "camera curve"],
        },
        {
            "id": "upper_gate_bridge_context",
            "claim": "Upper gate/bridge formation frames constrain candidate camera context and foreground overlap.",
            "original_runtime_evidence_ids": ["p1_route_upper_formation_11", "p1_route_upper_formation_12"],
            "godot_capture_stages": ["opening_music", "opening_delay"],
            "implementation_status": "candidate_camera_anchor",
            "can_drive_runtime_motion": False,
            "not_proven": ["complete enemy entry path", "first-control idle", "continuous camera movement"],
        },
        {
            "id": "leonard_story_walk",
            "claim": "STORY051 contains exactly one direct opening walk token, for SID_PLAYER0/Leonard.",
            "source_tokens": [str(event.get("source_token", "")) for event in direct_actor_events],
            "original_runtime_evidence_ids": ["opening_lower_formation_before_dialogue"],
            "godot_capture_stages": ["actor_walk_token"],
            "implementation_status": "current_godot_provisional_motion",
            "can_drive_runtime_motion": True,
            "not_proven": ["exact path coordinate semantics", "speed", "facing", "foot anchor"],
        },
        {
            "id": "dialogue_lower_context",
            "claim": "Dialogue actor/message id order is resource-derived and constrained by lower-formation original-runtime frames.",
            "dialogue_message_ids": [str(event.get("message_id", "")) for event in dialogue_events],
            "dialogue_actor_tokens": [str(event.get("actor_token", "")) for event in dialogue_events],
            "original_runtime_evidence_ids": [
                "opening_dialogue_leonard",
                "opening_dialogue_map_only_gap",
                "opening_dialogue_soldier",
            ],
            "godot_capture_stages": ["dialogue_message_363"],
            "implementation_status": "original_resource_dialogue_overlay",
            "can_drive_runtime_motion": False,
            "not_proven": ["original message box layout", "first-control idle"],
        },
        {
            "id": "status_and_first_control_handoff",
            "claim": "Status token order and Godot autoplay handoff are implemented as provisional queue consumption.",
            "original_runtime_evidence_ids": ["first_control_action_menu", "p1_route_action_menu_13"],
            "godot_capture_stages": ["status_tokens_setup", "winfail_board_refresh", "autoplay_first_control"],
            "implementation_status": "compressed_autoplay_handoff",
            "final_opening_capture_event": opening_capture.get("final_opening_timeline_summary", {}).get("current_event_id", ""),
            "final_autoplay_event": autoplay_capture.get("final_opening_timeline_summary", {}).get("current_event_id", ""),
            "can_drive_runtime_motion": False,
            "not_proven": ["original status handler side effects", "exact handoff frame", "first_control_idle_no_menu"],
        },
    ]


def _current_godot_consumption(
    runtime_capture_path: Path,
    opening_capture_path: Path,
    autoplay_capture_path: Path,
    runtime_capture: dict[str, Any],
    opening_capture: dict[str, Any],
    autoplay_capture: dict[str, Any],
) -> dict[str, Any]:
    runtime_contract = runtime_capture.get("final_runtime_contract_summary", {})
    opening_camera = opening_capture.get("final_opening_camera_summary", {})
    opening_choreography = opening_capture.get("final_opening_choreography_summary", {})
    autoplay_camera = autoplay_capture.get("final_opening_camera_summary", {})
    autoplay_choreography = autoplay_capture.get("final_opening_choreography_summary", {})
    opening_segment_records = _capture_segment_record_status(opening_capture)
    autoplay_segment_records = _capture_segment_record_status(autoplay_capture)
    opening_camera_records = _capture_camera_contract_status(opening_capture)
    autoplay_camera_records = _capture_camera_contract_status(autoplay_capture)
    return {
        "runtime_capture_path": runtime_capture_path.as_posix(),
        "opening_capture_path": opening_capture_path.as_posix(),
        "opening_autoplay_capture_path": autoplay_capture_path.as_posix(),
        "generated_capture_status": {
            "runtime_capture": str(runtime_capture.get("capture_status", "present")),
            "opening_capture": str(opening_capture.get("capture_status", "present")),
            "opening_autoplay_capture": str(autoplay_capture.get("capture_status", "present")),
        },
        "runtime_capture_count": runtime_capture.get("capture_count", 0),
        "opening_capture_count": opening_capture.get("capture_count", 0),
        "autoplay_capture_count": autoplay_capture.get("capture_count", 0),
        "opening_final_camera_stage": opening_camera.get("stage", ""),
        "autoplay_final_camera_stage": autoplay_camera.get("stage", ""),
        "autoplay_final_event": autoplay_capture.get("final_opening_timeline_summary", {}).get("current_event_id", ""),
        "map_object_spawn_count": runtime_capture.get("final_map_object_summary", {}).get("spawned_count", 0),
        "runtime_contract_opening_choreography_packet_schema": runtime_contract.get("opening_choreography_packet_schema", ""),
        "runtime_contract_opening_choreography_motion_driver_segments": runtime_contract.get("opening_choreography_motion_driver_segments", []),
        "opening_capture_choreography_packet_schema": opening_choreography.get("packet_schema", ""),
        "opening_capture_motion_driver_segments": opening_choreography.get("motion_driver_segments", []),
        "opening_capture_segment_record_stages": opening_segment_records,
        "opening_capture_camera_contract_stages": opening_camera_records,
        "autoplay_capture_choreography_packet_schema": autoplay_choreography.get("packet_schema", ""),
        "autoplay_capture_motion_driver_segments": autoplay_choreography.get("motion_driver_segments", []),
        "autoplay_capture_segment_record_stages": autoplay_segment_records,
        "autoplay_capture_camera_contract_stages": autoplay_camera_records,
        "runtime_consumption_status": "current_godot_provisional_presentation",
        "claim_limit": "Current Godot captures prove queue consumption and visible scaffolding only; they do not prove original choreography.",
    }


def _capture_segment_record_status(capture_manifest: dict[str, Any]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for capture in capture_manifest.get("captures", []):
        if not isinstance(capture, dict):
            continue
        presentation = capture.get("opening_presentation_summary", {})
        if not isinstance(presentation, dict):
            continue
        segments = presentation.get("choreography_segments", [])
        if not isinstance(segments, list):
            segments = []
        records.append(
            {
                "stage": str(capture.get("stage", "")),
                "segment_ids": presentation.get("choreography_segment_ids", []),
                "segment_record_count": len(segments),
                "segment_claims_present": all(
                    isinstance(segment, dict) and bool(str(segment.get("claim", "")))
                    for segment in segments
                ),
                "segment_implementation_statuses": [
                    str(segment.get("implementation_status", ""))
                    for segment in segments
                    if isinstance(segment, dict)
                ],
                "segment_not_proven": presentation.get("segment_not_proven", []),
            }
        )
    return records


def _capture_camera_contract_status(capture_manifest: dict[str, Any]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for capture in capture_manifest.get("captures", []):
        if not isinstance(capture, dict):
            continue
        camera = capture.get("opening_camera_summary", {})
        if not isinstance(camera, dict):
            continue
        stage_record = camera.get("current_stage_record", {})
        if not isinstance(stage_record, dict):
            stage_record = {}
        candidate_records = stage_record.get("candidate_camera_evidence_records", [])
        if not isinstance(candidate_records, list):
            candidate_records = []
        context_records = stage_record.get("context_only_evidence_records", [])
        if not isinstance(context_records, list):
            context_records = []
        records.append(
            {
                "stage": str(capture.get("stage", "")),
                "camera_stage": str(camera.get("stage", "")),
                "continuous_curve_status": str(camera.get("continuous_curve_status", "")),
                "candidate_anchor_sequence_count": len(camera.get("candidate_anchor_sequence", []))
                if isinstance(camera.get("candidate_anchor_sequence", []), list)
                else 0,
                "current_stage_record_schema": str(stage_record.get("schema", "")),
                "candidate_camera_evidence_ids": stage_record.get("candidate_camera_evidence_ids", []),
                "context_only_evidence_ids": stage_record.get("context_only_evidence_ids", []),
                "candidate_evidence_records_present": all(
                    isinstance(item, dict)
                    and bool(str(item.get("id", "")))
                    and bool(str(item.get("visual_state", "")))
                    and bool(str(item.get("runtime_use", "")))
                    for item in candidate_records
                ),
                "context_only_records_present": all(
                    isinstance(item, dict)
                    and bool(str(item.get("id", "")))
                    and bool(str(item.get("runtime_use", "")))
                    for item in context_records
                ),
                "transition_frames_are_context_only": (
                    "opening_transition_castle_wall_frame"
                    not in camera.get("evidence_ids", [])
                    and "opening_transition_castle_wall_frame"
                    in stage_record.get("context_only_evidence_ids", [])
                ),
                "current_stage_not_proven": stage_record.get("not_proven", []),
            }
        )
    return records


def write_markdown(packet: dict[str, Any], path: Path) -> None:
    header = evidence_index.format_header({
        "evidence": [{"tier": "runtime-measured", "scope": None}, {"tier": "resource-derived", "scope": None},
                     {"tier": "provisional", "scope": None}],
        "status": "record-only", "superseded_by": None, "functions": [],
        "tools": ["hsl_opening_choreography_packet.py", "hsltools/evidence/opening_choreography_packet.py"],
        "updated": str(packet["checked_date"]),
    })
    lines = [
        "# First Scene Opening Choreography Packet",
        "",
        header,
        "",
        "This packet is the current input contract for opening choreography work. It is generated from current evidence and is not a claim of original parity.",
        "",
        "## Current Truth",
        "",
        f"- Schema: `{packet['schema']}`",
        f"- Evidence tier: `{packet['evidence_tier']}`",
        f"- Direct STORY051 actor motion count: `{packet['script_timeline']['direct_actor_motion_count']}`",
        f"- Current Godot autoplay final event: `{packet['current_godot_consumption']['autoplay_final_event']}`",
        f"- Current Godot map object spawn count: `{packet['current_godot_consumption']['map_object_spawn_count']}`",
        f"- Opening capture segment-record stages: `{len(packet['current_godot_consumption'].get('opening_capture_segment_record_stages', []))}`",
        f"- Autoplay capture segment-record stages: `{len(packet['current_godot_consumption'].get('autoplay_capture_segment_record_stages', []))}`",
        f"- Opening capture camera-contract stages: `{len(packet['current_godot_consumption'].get('opening_capture_camera_contract_stages', []))}`",
        f"- Autoplay capture camera-contract stages: `{len(packet['current_godot_consumption'].get('autoplay_capture_camera_contract_stages', []))}`",
        "",
        "## Choreography Segments",
        "",
    ]
    for segment in packet["choreography_segments"]:
        lines.extend(
            [
                f"### {segment['id']}",
                "",
                f"- Claim: {segment['claim']}",
                f"- Implementation status: `{segment['implementation_status']}`",
                f"- Can drive runtime motion: `{str(segment['can_drive_runtime_motion']).lower()}`",
                f"- Original evidence ids: `{', '.join(segment.get('original_runtime_evidence_ids', []))}`",
                f"- Godot capture stages: `{', '.join(segment.get('godot_capture_stages', []))}`",
                f"- Not proven: `{', '.join(segment.get('not_proven', []))}`",
                "",
            ]
        )
    lines.extend(["## Actor Motion Status", ""])
    for actor in packet["actor_choreography"]:
        tokens = ", ".join(actor["direct_motion_tokens"]) if actor["direct_motion_tokens"] else "none"
        messages = ", ".join(actor["dialogue_message_ids"]) if actor["dialogue_message_ids"] else "none"
        lines.append(
            f"- `{actor['actor_token']}` / `{actor['actor_id']}`: `{actor['motion_status']}`; direct motion: `{tokens}`; dialogue ids: `{messages}`."
        )
    lines.extend(["", "## Missing Original Truth", ""])
    for item in packet["missing_original_truth"]:
        lines.append(f"- `{item}`")
    lines.extend(["", "## Forbidden Inferences", ""])
    for item in packet["forbidden_inferences"]:
        lines.append(f"- {item}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data: Any = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object: {path}")
    return data


def _load_json_or_missing_capture(path: Path, expected_schema: str) -> dict[str, Any]:
    if path.exists():
        return _load_json(path)
    return {
        "schema": expected_schema,
        "path": path.as_posix(),
        "evidence_tier": "godot-rendered-provisional",
        "capture_status": MISSING_CAPTURE_STATUS,
        "capture_count": 0,
        "captures": [],
        "missing_reason": "Generated capture manifest is ignored/local and has not been regenerated in this checkout.",
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visual-index", type=Path, default=DEFAULT_VISUAL_INDEX)
    parser.add_argument("--timeline", type=Path, default=DEFAULT_TIMELINE)
    parser.add_argument("--map-objects", type=Path, default=DEFAULT_MAP_OBJECTS)
    parser.add_argument("--map-object-visibility", type=Path, default=DEFAULT_MAP_OBJECT_VISIBILITY)
    parser.add_argument("--actor-walk", type=Path, default=DEFAULT_ACTOR_WALK)
    parser.add_argument("--runtime-capture", type=Path, default=DEFAULT_RUNTIME_CAPTURE)
    parser.add_argument("--opening-capture", type=Path, default=DEFAULT_OPENING_CAPTURE)
    parser.add_argument("--autoplay-capture", type=Path, default=DEFAULT_AUTOPLAY_CAPTURE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--markdown", type=Path, default=DEFAULT_MARKDOWN)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    packet = build_packet(args)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(packet, args.markdown)
    print(
        "opening choreography packet wrote "
        f"{args.output} segments={len(packet['choreography_segments'])} "
        f"direct_actor_motion={packet['script_timeline']['direct_actor_motion_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
