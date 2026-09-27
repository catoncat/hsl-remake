"""Validate actor walk-frame contact sheet outputs.

Registry task actor_walk_contact_sheet (family evidence): the tracked chapter-1 contact-sheet
report. Bodies moved verbatim from the former hsl_actor_walk_contact_sheet_check.py.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image

from hsltools.registry import Context, ScriptCheckTask


SCHEMA = "hsl_actor_walk_contact_sheet.v1"
DEFAULT_REPORT = Path("content/imported/hsl/chapter01/actor_walk_frames/contact_sheets/actor_walk_contact_sheet_manifest.json")
DEFAULT_ACTORS = ("001", "021", "023", "024", "026")


def _fail(message: str) -> None:
    raise SystemExit(f"actor walk contact sheet check failed: {message}")


def check_contact_sheet_report(report_path: Path, expected_actors: list[str] | None = None) -> dict[str, int]:
    with report_path.open("r", encoding="utf-8") as handle:
        report: dict[str, Any] = json.load(handle)

    if report.get("schema") != SCHEMA:
        _fail("unexpected schema")
    if report.get("evidence_tier") != "resource-derived":
        _fail("report evidence_tier must be resource-derived")
    grid_contract: dict[str, Any] = report.get("grid_contract", {})
    if grid_contract.get("semantic_status") != "candidate_unconfirmed":
        _fail("grid contract must keep facing semantics candidate_unconfirmed")

    expected = expected_actors or list(DEFAULT_ACTORS)
    actors: dict[str, Any] = report.get("actors", {})
    for actor_id in expected:
        actor = actors.get(actor_id)
        if not isinstance(actor, dict):
            _fail(f"missing actor sheet {actor_id}")
        if int(actor.get("row_count", 0)) != 5 or int(actor.get("column_count", 0)) != 6:
            _fail(f"actor {actor_id} sheet must be 5x6")
        if int(actor.get("frame_count", 0)) != 30:
            _fail(f"actor {actor_id} sheet must represent 30 frames")
        if actor.get("missing_cells", []):
            _fail(f"actor {actor_id} has missing cells")
        if actor.get("visual_review_status") != "contact_sheet_ready_for_human_review":
            _fail(f"actor {actor_id} visual_review_status is not ready")
        path = Path(str(actor.get("sheet_path", "")))
        if not path.exists():
            _fail(f"missing contact sheet image for {actor_id}: {path}")
        with Image.open(path) as image:
            if image.size != (int(actor.get("width", 0)), int(actor.get("height", 0))):
                _fail(f"actor {actor_id} contact sheet size mismatch")
            if image.getbbox() is None:
                _fail(f"actor {actor_id} contact sheet appears blank")
    return {"actor_count": len(expected)}


class ActorWalkContactSheetTask(ScriptCheckTask):
    name = 'actor_walk_contact_sheet'
    family = 'evidence'
    inputs = ()
    outputs = (DEFAULT_REPORT.as_posix(), DEFAULT_REPORT.parent.as_posix() + '/')
    replaces = (f'tools/hsl_actor_walk_contact_sheet_check.py {DEFAULT_REPORT.as_posix()} --actors ' + ' '.join(DEFAULT_ACTORS),)
    scripts = ('tools/hsltools/evidence/actor_walk_contact_sheet.py',)

    def verify(self, ctx: Context) -> None:
        summary = check_contact_sheet_report(DEFAULT_REPORT, list(DEFAULT_ACTORS))
        print(f"actor walk contact sheet ok: actors={summary['actor_count']} report={DEFAULT_REPORT}")


def tasks() -> list[ActorWalkContactSheetTask]:
    return [ActorWalkContactSheetTask()]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", nargs="?", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--actors", nargs="+", default=list(DEFAULT_ACTORS))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = check_contact_sheet_report(args.report, [str(actor).zfill(3) for actor in args.actors])
    print(f"actor walk contact sheet ok: actors={summary['actor_count']} report={args.report}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
