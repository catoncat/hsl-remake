#!/usr/bin/env python3
"""Validate Move spatial contract probe reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


SCHEMA = "hsl_move_spatial_contract_probe.v1"
DEFAULT_REPORT = Path("ignored/first-scene-dev-interaction-harness/latest/move_spatial_contract_probe.json")
ALLOWED_STATUSES = {"mismatch_provisional", "candidate_alignment"}


def _fail(message: str) -> None:
    raise SystemExit(f"move spatial contract probe check failed: {message}")


def check_probe_report(report_path: Path, repo_root: Path | None = None) -> dict[str, Any]:
    root = repo_root or Path.cwd()
    with report_path.open("r", encoding="utf-8") as handle:
        report: dict[str, Any] = json.load(handle)

    if report.get("schema") != SCHEMA:
        _fail("unexpected schema")
    if report.get("evidence_tier") != "runtime-measured-vs-provisional-godot-capture":
        _fail("unexpected evidence_tier")
    if "does not prove" not in str(report.get("claim_limit", "")):
        _fail("claim_limit must prevent parity overclaim")

    original = _require_object(report, "original")
    if original.get("evidence_id") != "move_overlay_primary":
        _fail("original evidence_id must be move_overlay_primary")
    if original.get("entry_status") != "confirmed":
        _fail("original Move evidence must be confirmed")
    if original.get("entry_evidence_tier") != "runtime-measured":
        _fail("original Move evidence must be runtime-measured")
    _check_image(original.get("image"), root, "original")

    godot = _require_object(report, "godot")
    if godot.get("capture_status") != "provisional_new_runtime_capture":
        _fail("Godot capture must remain provisional")
    _check_image(godot.get("image"), root, "godot")

    comparison = _require_object(report, "comparison")
    status = comparison.get("status")
    if status not in ALLOWED_STATUSES:
        _fail(f"unsupported comparison status: {status}")
    if not isinstance(comparison.get("bbox_iou_normalized"), (int, float)):
        _fail("comparison missing bbox_iou_normalized")
    if not isinstance(comparison.get("centroid_delta_normalized"), (int, float)):
        _fail("comparison missing centroid_delta_normalized")
    if status == "candidate_alignment" and comparison["bbox_iou_normalized"] < 0.55:
        _fail("candidate_alignment requires a minimum normalized bbox IoU")

    return {
        "status": status,
        "bbox_iou_normalized": comparison["bbox_iou_normalized"],
        "centroid_delta_normalized": comparison["centroid_delta_normalized"],
    }


def _require_object(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        _fail(f"missing object {key}")
    return value


def _check_image(image: Any, repo_root: Path, label: str) -> None:
    if not isinstance(image, dict):
        _fail(f"{label} image must be an object")
    path_value = image.get("path")
    if not isinstance(path_value, str) or not path_value:
        _fail(f"{label} image path missing")
    image_path = Path(path_value)
    if not image_path.is_absolute():
        image_path = repo_root / image_path
    if not image_path.exists():
        _fail(f"{label} image path does not exist: {path_value}")
    if int(image.get("width", 0)) <= 0 or int(image.get("height", 0)) <= 0:
        _fail(f"{label} image size invalid")
    if int(image.get("blue_pixel_count", 0)) <= 0:
        _fail(f"{label} image has no detected blue pixels")
    if int(image.get("significant_component_count", 0)) <= 0:
        _fail(f"{label} image has no significant blue components")
    if image.get("significant_bbox_normalized") is None:
        _fail(f"{label} image has no significant normalized bbox")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", nargs="?", type=Path, default=DEFAULT_REPORT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    summary = check_probe_report(args.report, repo_root)
    print(
        "move spatial contract probe ok: status={} iou={} centroid_delta={} report={}".format(
            summary["status"],
            summary["bbox_iou_normalized"],
            summary["centroid_delta_normalized"],
            args.report,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
