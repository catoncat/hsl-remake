#!/usr/bin/env python3
"""Build actor walk-frame contact sheets from the actor walk manifest."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


CONTACT_SHEET_SCHEMA = "hsl_actor_walk_contact_sheet.v1"
DEFAULT_MANIFEST = Path("content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json")
DEFAULT_OUTPUT_ROOT = Path("content/imported/hsl/chapter01/actor_walk_frames/contact_sheets")
DEFAULT_ACTORS = ("001", "021", "023", "024", "026")
CELL_SIZE = (112, 112)
HEADER_HEIGHT = 28
LABEL_HEIGHT = 18
GUTTER = 8


def build_contact_sheets(
    manifest_path: Path,
    output_root: Path,
    actor_ids: list[str] | None = None,
) -> dict[str, Any]:
    manifest = _load_json(manifest_path)
    actors: dict[str, Any] = manifest.get("actors", {})
    requested_actors = actor_ids or list(manifest.get("actor_ids", DEFAULT_ACTORS))
    output_root.mkdir(parents=True, exist_ok=True)

    sheet_entries: dict[str, Any] = {}
    for actor_id in requested_actors:
        actor = actors.get(actor_id)
        if not isinstance(actor, dict):
            raise SystemExit(f"missing actor in walk manifest: {actor_id}")
        output_path = output_root / f"{actor_id}_walk_contact_sheet.png"
        sheet_entries[actor_id] = _build_actor_sheet(actor, output_path)

    report = {
        "schema": CONTACT_SHEET_SCHEMA,
        "source_manifest": manifest_path.as_posix(),
        "output_root": output_root.as_posix(),
        "evidence_tier": "resource-derived",
        "actor_ids": requested_actors,
        "actors": sheet_entries,
        "grid_contract": {
            "rows": "source_facing_code_0_to_4",
            "columns": "pose_index_1_to_6",
            "conclusion": "resource filename grid is stable enough for ActorRuntime consumption",
            "semantic_status": "candidate_unconfirmed",
            "not_proven": [
                "which facing code means north/south/east/west",
                "exact pose cycle order used by the original renderer",
                "foot anchor and shadow anchor",
                "walk speed or frame timing",
            ],
        },
        "claim_limit": "Contact sheets prove a readable 5x6 source-frame grid per actor; they do not prove final facing semantics or animation timing.",
    }
    report_path = output_root / "actor_walk_contact_sheet_manifest.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def _build_actor_sheet(actor: dict[str, Any], output_path: Path) -> dict[str, Any]:
    actor_id = str(actor.get("actor_id", ""))
    frames_by_grid: dict[tuple[int, int], dict[str, Any]] = {}
    for frame in actor.get("frames", []):
        if not isinstance(frame, dict):
            continue
        key = (int(frame.get("facing_code", -1)), int(frame.get("pose_index", -1)))
        frames_by_grid[key] = frame

    width = GUTTER + 6 * (CELL_SIZE[0] + GUTTER)
    height = HEADER_HEIGHT + GUTTER + 5 * (CELL_SIZE[1] + LABEL_HEIGHT + GUTTER)
    sheet = Image.new("RGBA", (width, height), (28, 31, 35, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((GUTTER, 6), f"actor {actor_id}: rows=facing code 0..4, cols=pose 1..6", fill=(236, 236, 220, 255))

    missing: list[str] = []
    for facing_code in range(5):
        for pose_index in range(1, 7):
            x = GUTTER + (pose_index - 1) * (CELL_SIZE[0] + GUTTER)
            y = HEADER_HEIGHT + GUTTER + facing_code * (CELL_SIZE[1] + LABEL_HEIGHT + GUTTER)
            draw.rectangle((x, y, x + CELL_SIZE[0] - 1, y + CELL_SIZE[1] - 1), fill=(44, 47, 52, 255), outline=(94, 98, 105, 255))
            _draw_checkerboard(sheet, x + 8, y + 8, CELL_SIZE[0] - 16, CELL_SIZE[1] - 30)
            frame = frames_by_grid.get((facing_code, pose_index))
            if frame is None:
                missing.append(f"{facing_code}:{pose_index}")
                draw.text((x + 14, y + 42), "missing", fill=(255, 120, 120, 255))
            else:
                _paste_frame(sheet, Path(str(frame.get("png_path", ""))), x + 8, y + 8, CELL_SIZE[0] - 16, CELL_SIZE[1] - 30)
            draw.text((x + 8, y + CELL_SIZE[1] - 18), f"f{facing_code} p{pose_index}", fill=(236, 236, 220, 255))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output_path)
    return {
        "actor_id": actor_id,
        "sheet_path": output_path.as_posix(),
        "width": width,
        "height": height,
        "row_count": 5,
        "column_count": 6,
        "frame_count": len(actor.get("frames", [])),
        "missing_cells": missing,
        "evidence_tier": "resource-derived",
        "visual_review_status": "contact_sheet_ready_for_human_review",
        "semantic_status": "candidate_unconfirmed",
    }


def _paste_frame(sheet: Image.Image, png_path: Path, x: int, y: int, max_width: int, max_height: int) -> None:
    if not png_path.exists():
        return
    with Image.open(png_path) as frame:
        frame_rgba = frame.convert("RGBA")
        frame_rgba.thumbnail((max_width, max_height), Image.Resampling.NEAREST)
        paste_x = x + (max_width - frame_rgba.width) // 2
        paste_y = y + (max_height - frame_rgba.height) // 2
        sheet.alpha_composite(frame_rgba, (paste_x, paste_y))


def _draw_checkerboard(sheet: Image.Image, x: int, y: int, width: int, height: int) -> None:
    draw = ImageDraw.Draw(sheet)
    tile = 8
    for cy in range(y, y + height, tile):
        for cx in range(x, x + width, tile):
            odd = ((cx - x) // tile + (cy - y) // tile) % 2
            color = (74, 78, 84, 255) if odd else (62, 66, 72, 255)
            draw.rectangle((cx, cy, min(cx + tile - 1, x + width - 1), min(cy + tile - 1, y + height - 1)), fill=color)


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data: Any = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object: {path}")
    return data


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--actors", nargs="+", default=list(DEFAULT_ACTORS))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    actor_ids = [str(actor).zfill(3) for actor in args.actors]
    report = build_contact_sheets(args.manifest, args.output_root, actor_ids)
    print(
        "actor walk contact sheets ok: actors={} output={}".format(
            len(report["actors"]),
            args.output_root,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
