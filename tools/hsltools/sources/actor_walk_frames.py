"""Actor walk frames from the original PAK: the SHAPEDEF walking groups of an actor, its
`@:\\shape\\NNN-FPPPP.shp` records, the decoded frame PNGs and the hsl_actor_walk_manifest.v1
manifest under content/imported/hsl/<chapter>/actor_walk_frames/.

is_walking_shape tells the level generators whether an EVEF enemy has a SHAPEDEF walking group
(otherwise it is a static shape, docs/evidence_packets/static_reverse/original_static_shape_enemy.md);
collect_actor_walk_records / build_actor_walk_manifest / write_manifest are the import path the
level actors, story scenes and job casts share. The command line is tools/hsl_actor_walk_manifest.py.
Bodies moved verbatim from that script.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path
from typing import Any

from hsltools.paths import ORIGINAL_PAK
from hsltools.sources.pak import (
    find_decoded_paks_packages,
    find_paks_record_by_name,
    read_paks_record_bytes,
)
from hsltools.sources.shp import parse_shp, write_shp_preview


ACTOR_WALK_SCHEMA = "hsl_actor_walk_manifest.v1"
DEFAULT_INPUT = ORIGINAL_PAK
DEFAULT_ACTORS = ("001", "021", "023", "024", "025", "026", "039", "002")
DEFAULT_OUTPUT_ROOT = Path("content/imported/hsl/chapter01/actor_walk_frames")
DEFAULT_RES_ROOT = "res://content/imported/hsl/chapter01/actor_walk_frames"
WALK_RECORD_RE = re.compile(r"^@:\\shape\\(?P<actor>\d{3})-(?P<facing>[0-4])(?P<pose>\d{4})\.shp$", re.IGNORECASE)


SHAPE_DEFINITIONS = Path("content/imported/hsl/global/tables/SHAPEDEF.TXT")


def _shape_fields(actor_id: str) -> dict[str, str]:
    """The SHAPEDEF.TXT block of an actor: the block declared for its own SID (`code =
    SID_ENEMYnnn`, the obj_Data6 its objects carry), else the first block whose stand shape
    carries the actor's number (the registered rows 001-020 are keyed SID_PLAYERn). A row may
    wear another row's frames: the level-37 guardians (SID_ENEMY066 -> SHAPE\\050-*,
    SID_ENEMY067 -> MAGIC\\MIN12_11.SHP) and the enemy 克羅蒂 (SID_ENEMY053 -> SHAPE\\009-*,
    as her obs objects' shape field also says; SHAPE\\053-* is SID_PLAYER17's, row 018)."""
    blocks = [{k: v.strip() for k, v in re.findall(r"^\s*(\w+)\s*=\s*([^;\r\n]+)", block, re.M)}
              for block in SHAPE_DEFINITIONS.read_bytes().decode("cp950").split("[define]")[1:]]
    for fields in blocks:
        if fields.get("code") == f"SID_ENEMY{actor_id}":
            return fields
    prefixes = {actor_id, str(int(actor_id))}
    for fields in blocks:
        stand = fields.get("stand", "").lower()
        if any(stand.startswith(f"shape\\{prefix}-") for prefix in prefixes):
            return fields
    raise ValueError(f"missing actor shape definition: {actor_id}")


def sprite_prefix(actor_id: str) -> str:
    """The SHAPE number the actor's walk groups are stored under: its own number, or the row whose
    frames its SHAPEDEF block declares (066 -> 050)."""
    match = re.fullmatch(r"shape\\(\d{3})-00001\.shp", _shape_fields(actor_id).get("stand", ""), re.I)
    if not match:
        raise ValueError(f"actor {actor_id} does not use the standard stand group")
    return match[1]


def standing_shape_spec(actor_id: str) -> dict[str, str]:
    """Return a source standing shape when SHAPEDEF has no five walk groups."""
    fields = _shape_fields(actor_id)
    try:
        actor_group_specs(actor_id)
    except ValueError:
        stand = fields.get("stand", "")
        if re.fullmatch(r"shape\\\d{3}-00001.shp", stand, re.I):
            raise
        return {"source_member": "@:\\" + stand.lower(), "reason": "standing_shape_without_walk_groups"}
    raise ValueError(f"actor {actor_id} has walk groups; standing-only path is not applicable")


def actor_group_specs(actor_id: str) -> dict[int, dict[str, int | str]]:
    fields = _shape_fields(actor_id)
    prefix = sprite_prefix(actor_id)
    groups: dict[int, dict[str, int | str]] = {}
    for action in ("stand", "walk_up", "walk_down", "walk_left", "walk_right"):
        match = re.fullmatch(r"shape\\" + prefix + r"-([0-4])0001.shp", fields[action], re.I)
        frame_count = int(fields[action + "_num"])
        if not match or frame_count <= 0 or frame_count > 9999:
            raise ValueError(f"unsupported actor shape definition: {actor_id}/{action}")
        groups[int(match[1])] = {"action": action, "frame_count": frame_count}
    if len(groups) != 5:
        raise ValueError(f"ambiguous actor shape groups: {actor_id}")
    return groups


def has_walk_shapes(actor_id: str) -> bool:
    """True when SHAPEDEF.TXT defines the actor's stand/walk groups."""
    try:
        actor_group_specs(actor_id)
    except ValueError:
        return False
    return True


def is_walking_shape(shape_resource: str) -> bool:
    """True when an object's shape is an actor frame set (SHAPE\\NNN-00001.SHP) with
    SHAPEDEF walk groups; enemy-process objects wearing other shapes (level 12's
    Enemy101 船殼 hull pieces use SHAPE11\\18_DOOR01.SHP) are static shapes."""
    match = re.fullmatch(r"(\d{3})-00001\.shp", shape_resource.split("\\")[-1], re.I)
    return bool(match) and has_walk_shapes(match[1])


ACTOR_TEMPLATES = Path("content/generated/hsl/actors")


def object_actor_code(raw: object) -> str:
    """The PLAYERS row an object's obj_Data7 names, zero-filled ('' when it is not a number):
    decimal, or 0x-hex with flag bits above the row (level 12／26's hull pieces carry
    0x80000065 = row 101 — the registry records row 101, opening snapshot +0xa2)."""
    text = str(raw).strip()
    try:
        value = int(text, 16) if text.lower().startswith("0x") else int(text, 10)
    except ValueError:
        return ""
    return str(value & 0xffff).zfill(3)


def standing_actor_code(row: dict) -> str:
    """The PLAYERS code of an EVEF/header enemy-process object that stands still in its own
    SHAPEDEF standing frame and has a generated actor template (level 80's Enemy068 怨念體,
    SHAPE\\68-001.SHP): such an object is a PlayLoop unit, not a stand sprite. '' otherwise
    (level 12／26's Enemy101 hull pieces and level 18's Enemy100 door wear SHAPE11\\18_DOOR01.SHP,
    the stand shape of their SHAPEDEF blocks, and are units like it)."""
    if row.get("role_from_process") != "enemy_object" or not row.get("shape_resource"):
        return ""
    code = object_actor_code(row.get("object_data_fields", {}).get("obj_Data7", ""))
    if not code or is_walking_shape(str(row["shape_resource"])):
        return ""
    if not (ACTOR_TEMPLATES / f"{code}.json").is_file():
        return ""
    try:
        member = standing_shape_spec(code)["source_member"]
    except ValueError:
        return ""
    return code if member == "@:\\" + str(row["shape_resource"]).lower() else ""


def actor_groups(actor_id: str) -> dict[int, str]:
    return {code: str(spec["action"]) for code, spec in actor_group_specs(actor_id).items()}


def expected_walk_record_name(prefix: str, facing_code: int, pose_index: int) -> str:
    """PAK member of one walk frame; `prefix` is the actor's sprite_prefix."""
    return f"@:\\shape\\{prefix}-{facing_code}{pose_index:04d}.shp"


def parse_walk_record_name(name: str) -> dict[str, int | str] | None:
    match = WALK_RECORD_RE.match(name)
    if not match:
        return None
    return {
        "actor_id": match.group("actor"),
        "facing_code": int(match.group("facing")),
        "pose_index": int(match.group("pose")),
    }


def collect_actor_walk_records(input_path: Path, actor_ids: list[str]) -> dict[str, bytes]:
    packages = find_decoded_paks_packages(input_path)
    if not packages:
        raise SystemExit(f"no decoded PAKS packages found under {input_path}")

    records: dict[str, bytes] = {}
    for actor_id in actor_ids:
        try:
            specs = actor_group_specs(actor_id)
        except ValueError:
            standing = standing_shape_spec(actor_id)
            requested_name = standing["source_member"]
            matches: list[tuple[dict[str, Any], dict[str, int | str]]] = []
            for package in packages:
                record = find_paks_record_by_name(package["records"], requested_name)
                if record is not None:
                    matches.append((package, record))
            if not matches:
                continue
            if len(matches) > 1:
                sources = ", ".join(package["relative_path"] for package, _ in matches)
                raise SystemExit(f"ambiguous actor standing record {requested_name} in {sources}")
            package, record = matches[0]
            records[requested_name] = read_paks_record_bytes(
                package["path"], record,
                data_end_offset=int(package["paks"]["candidate_index_offset"]),
            )
            continue
        prefix = sprite_prefix(actor_id)
        for facing_code in range(5):
            for pose_index in range(1, int(specs[facing_code]["frame_count"]) + 1):
                requested_name = expected_walk_record_name(prefix, facing_code, pose_index)
                matches: list[tuple[dict[str, Any], dict[str, int | str]]] = []
                for package in packages:
                    record = find_paks_record_by_name(package["records"], requested_name)
                    if record is not None:
                        matches.append((package, record))
                if not matches:
                    continue
                if len(matches) > 1:
                    sources = ", ".join(package["relative_path"] for package, _ in matches)
                    raise SystemExit(f"ambiguous actor walk record {requested_name} in {sources}")
                package, record = matches[0]
                records[requested_name] = read_paks_record_bytes(
                    package["path"],
                    record,
                    data_end_offset=int(package["paks"]["candidate_index_offset"]),
                )
    return records


def build_actor_walk_manifest(
    actor_ids: list[str],
    records: dict[str, bytes],
    output_root: Path,
    *,
    decode_png: bool = True,
    res_root: str = DEFAULT_RES_ROOT,
) -> dict[str, Any]:
    actors: dict[str, Any] = {}
    for actor_id in actor_ids:
        try:
            specs = actor_group_specs(actor_id)
        except ValueError:
            standing = standing_shape_spec(actor_id)
            source_member = standing["source_member"]
            payload = records.get(source_member)
            frames: list[dict[str, Any]] = []
            missing = [] if payload is not None else [source_member]
            if payload is not None:
                if len(payload) < 36 or payload[:4] != b"TLHS":
                    raise ValueError(f"invalid SHP header: {source_member}")
                stem = source_member.rsplit("\\", 1)[-1].rsplit(".", 1)[0]
                filename = f"{actor_id}-{stem.split('-', 1)[1]}.png" if "-" in stem else f"{actor_id}-{stem}.png"
                output_path = output_root / actor_id / filename
                if decode_png:
                    write_shp_preview(payload, parse_shp(payload), output_path)
                frames.append({
                    "index": 0,
                    "draw_origin": list(struct.unpack_from("<ii", payload, 0x1C)),
                    "draw_origin_evidence": "static-derived:0x45fa75-0x45fab4",
                    "actor_id": actor_id,
                    "source_member": source_member,
                    "png_path": output_path.as_posix(),
                    "res_path": f"{res_root.rstrip('/')}/{actor_id}/{filename}",
                    "animation_state": "idle",
                    "direction": "0",
                    "facing_code": int(stem.split("-", 1)[1][0]) if "-" in stem else 0,
                    "pose_index": 1,
                    "tier": "resource-derived",
                    "unresolved_semantics": ["standing_shape_direction_unconfirmed", "header_0x10_transparency_unconfirmed"],
                })
            fallback_src = frames[0]["res_path"] if frames else ""
            actors[actor_id] = {
                "actor_id": actor_id, "frame_count": len(frames), "expected_frame_count": 1,
                "standing_only": True, "frames": frames,
                "animations": {"idle": {"0": {"frames": [0] if frames else [], "fps": 8,
                                                   "timing_evidence_tier": "provisional", "loop": True,
                                                   "tier": "resource-derived", "source_field": "stand"}}, "walk": {}},
                "facing_set": {"0": {"source_facing_code": frames[0]["facing_code"] if frames else 1,
                                       "semantic_status": "stand", "tier": "resource-derived"}},
                "fallback": {"mode": "single_frame", "src": fallback_src,
                             "reason": standing["reason"], "tier": "resource-derived" if frames else "provisional"},
                "missing_source_members": missing,
                "unresolved": ["standing_shape_direction_unconfirmed", "header_0x10_transparency_unconfirmed"],
            }
            continue
        groups = {code: str(spec["action"]) for code, spec in specs.items()}
        prefix = sprite_prefix(actor_id)
        frames: list[dict[str, Any]] = []
        animations: dict[str, dict[str, Any]] = {"idle": {}, "walk": {}}
        missing: list[str] = []

        for facing_code in range(5):
            walk_frame_indexes: list[int] = []
            for pose_index in range(1, int(specs[facing_code]["frame_count"]) + 1):
                source_member = expected_walk_record_name(prefix, facing_code, pose_index)
                payload = records.get(source_member)
                if payload is None:
                    missing.append(source_member)
                    continue
                frame_index = len(frames)
                filename = f"{prefix}-{facing_code}000{pose_index}.png"
                output_path = output_root / actor_id / filename
                res_path = f"{res_root.rstrip('/')}/{actor_id}/{filename}"
                if decode_png:
                    shp = parse_shp(payload)
                    write_shp_preview(payload, shp, output_path)
                if len(payload) < 36 or payload[:4] != b"TLHS":
                    raise ValueError(f"invalid SHP header: {source_member}")
                origin = list(struct.unpack_from("<ii", payload, 0x1C))
                frame = {
                    "index": frame_index,
                    "draw_origin": origin,
                    "draw_origin_evidence": "static-derived:0x45fa75-0x45fab4",
                    "actor_id": actor_id,
                    "source_member": source_member,
                    "png_path": output_path.as_posix(),
                    "res_path": res_path,
                    "animation_state": "idle" if groups[facing_code] == "stand" else "walk",
                    "direction": "0" if groups[facing_code] == "stand" else groups[facing_code].removeprefix("walk_"),
                    "facing_code": facing_code,
                    "pose_index": pose_index,
                    "tier": "resource-derived",
                    "unresolved_semantics": [
                        "pose_cycle_order_unconfirmed",
                        "header_0x10_transparency_unconfirmed",
                    ],
                }
                frames.append(frame)
                walk_frame_indexes.append(frame_index)

            action = groups[facing_code]
            state = "idle" if action == "stand" else "walk"
            direction = "0" if state == "idle" else action.removeprefix("walk_")
            animations[state][direction] = {
                "frames": walk_frame_indexes,
                "fps": 8,
                "timing_evidence_tier": "provisional",
                "loop": True,
                "tier": "resource-derived",
                "source_field": action,
            }

        fallback_src = f"{res_root.rstrip('/')}/{actor_id}/{prefix}-00001.png"
        actors[actor_id] = {
            "actor_id": actor_id,
            "frame_count": len(frames),
            "expected_frame_count": sum(int(spec["frame_count"]) for spec in specs.values()),
            "frames": frames,
            "animations": animations,
            "facing_set": {
                str(code): {
                    "source_facing_code": code,
                    "semantic_status": groups[code],
                    "tier": "resource-derived",
                }
                for code in range(5)
            },
            "fallback": {
                "mode": "single_frame",
                "src": fallback_src,
                "reason": "fallback remains valid until facing/pose semantics are consumed by runtime",
                "tier": "provisional" if len(frames) == 0 else "resource-derived",
            },
            "missing_source_members": missing,
            "unresolved": [
                "pose_cycle_order_unconfirmed",
                "header_0x10_transparency_unconfirmed",
            ],
        }

    return {
        "schema": ACTOR_WALK_SCHEMA,
        "evidence_tier": "resource-derived",
        "actor_ids": actor_ids,
        "actors": actors,
        "shape_definitions": str(SHAPE_DEFINITIONS),
        "shape_definitions_sha256": hashlib.sha256(SHAPE_DEFINITIONS.read_bytes()).hexdigest(),
        "source_policy": "local private original PAK actor SHP records decoded into PNG previews and a manifest; frame semantics remain candidate until visual/static review",
        "unresolved_semantics": [
            "pose_cycle_order_unconfirmed",
            "walk_speed_and_timing_unconfirmed",
        ],
    }


def write_manifest(manifest: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
