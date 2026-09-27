#!/usr/bin/env python3
"""Compare original-runtime and Godot Move overlay screen-space geometry.

This is a preflight guard, not a visual parity claim. It detects saturated blue
Move-grid pixels in the confirmed original runtime capture and the current
Godot runtime capture, then writes compact geometry metrics.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image


SCHEMA = "hsl_move_spatial_contract_probe.v1"
DEFAULT_EVIDENCE_MANIFEST = Path(
    "docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.json"
)
DEFAULT_ORIGINAL_EVIDENCE_ID = "move_overlay_primary"
DEFAULT_GODOT_CAPTURE = Path("ignored/first-scene-dev-interaction-harness/latest/03_move_overlay_640x480.png")
DEFAULT_OUTPUT = Path("ignored/first-scene-dev-interaction-harness/latest/move_spatial_contract_probe.json")

DEFAULT_BLUE_THRESHOLD = {
    "min_alpha": 64,
    "min_blue": 175,
    "max_red": 70,
    "min_blue_minus_red": 110,
    "min_blue_minus_green": 40,
}

CANDIDATE_MIN_IOU = 0.55
CANDIDATE_MAX_CENTROID_DELTA = 0.12
CANDIDATE_MIN_AREA_RATIO = 0.65
CANDIDATE_MAX_AREA_RATIO = 1.55


def build_probe_report(
    repo_root: Path,
    evidence_manifest: Path,
    original_evidence_id: str,
    godot_capture: Path,
    min_component_area: int = 48,
) -> dict[str, Any]:
    manifest = _load_json(_resolve_path(repo_root, evidence_manifest))
    original_entry = _find_evidence_entry(manifest, original_evidence_id)
    original_path = _resolve_path(repo_root, Path(str(original_entry["file"])))
    godot_path = _resolve_path(repo_root, godot_capture)

    original_image = analyze_blue_geometry(original_path, repo_root, min_component_area)
    godot_image = analyze_blue_geometry(godot_path, repo_root, min_component_area)
    comparison = compare_geometry(original_image, godot_image)

    return {
        "schema": SCHEMA,
        "generated_by": "tools/hsl_move_spatial_contract_probe.py",
        "evidence_tier": "runtime-measured-vs-provisional-godot-capture",
        "purpose": (
            "Quantify whether the current Godot Move overlay screen-space geometry "
            "matches the confirmed local original-runtime Move overlay baseline."
        ),
        "threshold": DEFAULT_BLUE_THRESHOLD,
        "min_component_area": min_component_area,
        "original": {
            "evidence_manifest": _repo_relative(_resolve_path(repo_root, evidence_manifest), repo_root),
            "evidence_id": original_evidence_id,
            "entry_status": original_entry.get("status"),
            "entry_evidence_tier": original_entry.get("evidence_tier"),
            "visual_state": original_entry.get("visual_state"),
            "use_for": original_entry.get("use_for", []),
            "not_for": original_entry.get("not_for", []),
            "image": original_image,
        },
        "godot": {
            "capture_status": "provisional_new_runtime_capture",
            "image": godot_image,
        },
        "comparison": comparison,
        "claim_limit": (
            "A valid report proves only that the chosen original and Godot screenshots "
            "were measured with the same saturated-blue detector. It does not prove "
            "movement rules, pathfinding, hit testing, animation timing, or visual parity."
        ),
        "next_gate": (
            "If status is mismatch_provisional, do not accept Move overlay, camera crop, "
            "grid projection, hit-test, or actor-foot-anchor parity from smoke tests alone."
        ),
    }


def analyze_blue_geometry(image_path: Path, repo_root: Path, min_component_area: int) -> dict[str, Any]:
    with Image.open(image_path) as image:
        rgba = image.convert("RGBA")
        width, height = rgba.size
        blue_pixels: set[tuple[int, int]] = set()
        for y in range(height):
            for x in range(width):
                if _is_move_blue(rgba.getpixel((x, y))):
                    blue_pixels.add((x, y))

    components = _connected_components(blue_pixels)
    significant = [component for component in components if component["area"] >= min_component_area]
    significant_pixels = sum(component["area"] for component in significant)

    raw_bbox = _bbox_from_points(blue_pixels)
    significant_bbox = _bbox_from_components(significant)
    largest = components[0] if components else None

    return {
        "path": _repo_relative(image_path, repo_root),
        "width": width,
        "height": height,
        "blue_pixel_count": len(blue_pixels),
        "blue_coverage": _ratio(len(blue_pixels), width * height),
        "blue_bbox": _bbox_as_list(raw_bbox),
        "blue_bbox_normalized": _normalize_bbox(raw_bbox, width, height),
        "blue_centroid": _centroid_from_points(blue_pixels),
        "blue_centroid_normalized": _normalize_point(_centroid_from_points(blue_pixels), width, height),
        "component_count": len(components),
        "significant_component_count": len(significant),
        "significant_blue_pixel_count": significant_pixels,
        "significant_blue_coverage": _ratio(significant_pixels, width * height),
        "significant_bbox": _bbox_as_list(significant_bbox),
        "significant_bbox_normalized": _normalize_bbox(significant_bbox, width, height),
        "significant_centroid": _centroid_from_components(significant),
        "significant_centroid_normalized": _normalize_point(
            _centroid_from_components(significant),
            width,
            height,
        ),
        "largest_component": largest,
        "top_component_areas": [component["area"] for component in components[:12]],
    }


def compare_geometry(original: dict[str, Any], godot: dict[str, Any]) -> dict[str, Any]:
    original_bbox = original.get("significant_bbox_normalized") or original.get("blue_bbox_normalized")
    godot_bbox = godot.get("significant_bbox_normalized") or godot.get("blue_bbox_normalized")
    original_centroid = original.get("significant_centroid_normalized") or original.get("blue_centroid_normalized")
    godot_centroid = godot.get("significant_centroid_normalized") or godot.get("blue_centroid_normalized")

    bbox_iou = _bbox_iou(original_bbox, godot_bbox)
    centroid_delta = _point_delta(original_centroid, godot_centroid)
    original_area = _bbox_area(original_bbox)
    godot_area = _bbox_area(godot_bbox)
    bbox_area_ratio = _safe_ratio(godot_area, original_area)
    coverage_ratio = _safe_ratio(godot.get("significant_blue_coverage"), original.get("significant_blue_coverage"))

    candidate = (
        bbox_iou >= CANDIDATE_MIN_IOU
        and centroid_delta <= CANDIDATE_MAX_CENTROID_DELTA
        and CANDIDATE_MIN_AREA_RATIO <= bbox_area_ratio <= CANDIDATE_MAX_AREA_RATIO
    )
    status = "candidate_alignment" if candidate else "mismatch_provisional"
    assessment = (
        "Godot Move overlay geometry is close enough for a later semantic parity review."
        if candidate
        else "Godot Move overlay geometry is not aligned with the original-runtime baseline."
    )

    return {
        "status": status,
        "assessment": assessment,
        "bbox_iou_normalized": round(bbox_iou, 6),
        "centroid_delta_normalized": round(centroid_delta, 6),
        "godot_to_original_bbox_area_ratio": round(bbox_area_ratio, 6),
        "godot_to_original_blue_coverage_ratio": round(coverage_ratio, 6),
        "original_significant_component_count": original.get("significant_component_count", 0),
        "godot_significant_component_count": godot.get("significant_component_count", 0),
        "candidate_thresholds": {
            "min_bbox_iou_normalized": CANDIDATE_MIN_IOU,
            "max_centroid_delta_normalized": CANDIDATE_MAX_CENTROID_DELTA,
            "min_bbox_area_ratio": CANDIDATE_MIN_AREA_RATIO,
            "max_bbox_area_ratio": CANDIDATE_MAX_AREA_RATIO,
        },
        "scale_note": (
            "The original capture and Godot capture can have different pixel scales; "
            "comparison metrics use normalized screen-space geometry."
        ),
    }


def _connected_components(points: set[tuple[int, int]]) -> list[dict[str, Any]]:
    remaining = set(points)
    components: list[dict[str, Any]] = []
    while remaining:
        start = remaining.pop()
        stack = [start]
        area = 0
        min_x = max_x = start[0]
        min_y = max_y = start[1]
        sum_x = 0
        sum_y = 0
        while stack:
            x, y = stack.pop()
            area += 1
            sum_x += x
            sum_y += y
            min_x = min(min_x, x)
            max_x = max(max_x, x)
            min_y = min(min_y, y)
            max_y = max(max_y, y)
            for neighbor in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
        components.append(
            {
                "area": area,
                "bbox": [min_x, min_y, max_x, max_y],
                "centroid": [round(sum_x / area, 3), round(sum_y / area, 3)],
            }
        )
    components.sort(key=lambda item: int(item["area"]), reverse=True)
    return components


def _is_move_blue(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    return (
        a >= DEFAULT_BLUE_THRESHOLD["min_alpha"]
        and b >= DEFAULT_BLUE_THRESHOLD["min_blue"]
        and r <= DEFAULT_BLUE_THRESHOLD["max_red"]
        and b - r >= DEFAULT_BLUE_THRESHOLD["min_blue_minus_red"]
        and b - g >= DEFAULT_BLUE_THRESHOLD["min_blue_minus_green"]
    )


def _bbox_from_points(points: set[tuple[int, int]]) -> tuple[int, int, int, int] | None:
    if not points:
        return None
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return (min(xs), min(ys), max(xs), max(ys))


def _bbox_from_components(components: list[dict[str, Any]]) -> tuple[int, int, int, int] | None:
    if not components:
        return None
    boxes = [component["bbox"] for component in components]
    return (
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    )


def _bbox_as_list(bbox: tuple[int, int, int, int] | None) -> list[int] | None:
    return list(bbox) if bbox else None


def _normalize_bbox(bbox: tuple[int, int, int, int] | None, width: int, height: int) -> list[float] | None:
    if bbox is None:
        return None
    x0, y0, x1, y1 = bbox
    return [
        round(x0 / width, 6),
        round(y0 / height, 6),
        round((x1 + 1) / width, 6),
        round((y1 + 1) / height, 6),
    ]


def _centroid_from_points(points: set[tuple[int, int]]) -> list[float] | None:
    if not points:
        return None
    return [
        round(sum(point[0] for point in points) / len(points), 3),
        round(sum(point[1] for point in points) / len(points), 3),
    ]


def _centroid_from_components(components: list[dict[str, Any]]) -> list[float] | None:
    total_area = sum(int(component["area"]) for component in components)
    if total_area <= 0:
        return None
    sum_x = 0.0
    sum_y = 0.0
    for component in components:
        area = int(component["area"])
        centroid = component["centroid"]
        sum_x += float(centroid[0]) * area
        sum_y += float(centroid[1]) * area
    return [round(sum_x / total_area, 3), round(sum_y / total_area, 3)]


def _normalize_point(point: list[float] | None, width: int, height: int) -> list[float] | None:
    if point is None:
        return None
    return [round(float(point[0]) / width, 6), round(float(point[1]) / height, 6)]


def _bbox_iou(a: list[float] | None, b: list[float] | None) -> float:
    if not a or not b:
        return 0.0
    ix0 = max(a[0], b[0])
    iy0 = max(a[1], b[1])
    ix1 = min(a[2], b[2])
    iy1 = min(a[3], b[3])
    intersection = max(0.0, ix1 - ix0) * max(0.0, iy1 - iy0)
    union = _bbox_area(a) + _bbox_area(b) - intersection
    return _safe_ratio(intersection, union)


def _bbox_area(bbox: list[float] | None) -> float:
    if not bbox:
        return 0.0
    return max(0.0, bbox[2] - bbox[0]) * max(0.0, bbox[3] - bbox[1])


def _point_delta(a: list[float] | None, b: list[float] | None) -> float:
    if not a or not b:
        return 1.0
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2)


def _ratio(numerator: float, denominator: float) -> float:
    return round(_safe_ratio(numerator, denominator), 8)


def _safe_ratio(numerator: Any, denominator: Any) -> float:
    try:
        numerator_f = float(numerator)
        denominator_f = float(denominator)
    except (TypeError, ValueError):
        return 0.0
    if denominator_f == 0:
        return 0.0
    return numerator_f / denominator_f


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        data: Any = json.load(handle)
    if not isinstance(data, dict):
        raise SystemExit(f"expected JSON object: {path}")
    return data


def _find_evidence_entry(manifest: dict[str, Any], evidence_id: str) -> dict[str, Any]:
    evidence = manifest.get("evidence")
    if not isinstance(evidence, list):
        raise SystemExit("visual evidence manifest has no evidence list")
    for entry in evidence:
        if isinstance(entry, dict) and entry.get("id") == evidence_id:
            if not isinstance(entry.get("file"), str) or not entry["file"]:
                raise SystemExit(f"evidence entry {evidence_id} has no file")
            return entry
    raise SystemExit(f"missing evidence entry: {evidence_id}")


def _resolve_path(repo_root: Path, path: Path) -> Path:
    return path if path.is_absolute() else repo_root / path


def _repo_relative(path: Path, repo_root: Path) -> str:
    try:
        return path.resolve().relative_to(repo_root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-manifest", type=Path, default=DEFAULT_EVIDENCE_MANIFEST)
    parser.add_argument("--original-evidence-id", default=DEFAULT_ORIGINAL_EVIDENCE_ID)
    parser.add_argument("--godot-capture", type=Path, default=DEFAULT_GODOT_CAPTURE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--min-component-area", type=int, default=48)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parents[1]
    report = build_probe_report(
        repo_root=repo_root,
        evidence_manifest=args.evidence_manifest,
        original_evidence_id=args.original_evidence_id,
        godot_capture=args.godot_capture,
        min_component_area=args.min_component_area,
    )
    output = _resolve_path(repo_root, args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    comparison = report["comparison"]
    print(
        "move spatial contract probe wrote {} status={} iou={} centroid_delta={}".format(
            _repo_relative(output, repo_root),
            comparison["status"],
            comparison["bbox_iou_normalized"],
            comparison["centroid_delta_normalized"],
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
