"""Validate the actor walk-frame manifest generated from original SHP records.

Registry tasks actor_walk_manifest:<chapter01|shared> (family evidence): the two tracked
manifests and their expected actor lists. Bodies moved verbatim from the former hsl_actor_walk_manifest_check.py.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from hsltools.registry import Context, ScriptCheckTask


SCHEMA = "hsl_actor_walk_manifest.v1"
DEFAULT_MANIFEST = Path("content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json")
DEFAULT_ACTORS = ("001", "021", "023", "024", "025", "026", "039", "002")


def _fail(message: str) -> None:
    raise SystemExit(f"actor walk manifest check failed: {message}")


def _is_png(path: Path) -> bool:
    with path.open("rb") as handle:
        return handle.read(8) == b"\x89PNG\r\n\x1a\n"


def check_actor_walk_manifest(manifest_path: Path, expected_actors: list[str] | None = None) -> dict[str, int]:
    with manifest_path.open("r", encoding="utf-8") as handle:
        manifest: dict[str, Any] = json.load(handle)

    if manifest.get("schema") != SCHEMA:
        _fail("unexpected schema")
    if manifest.get("evidence_tier") != "resource-derived":
        _fail("manifest evidence_tier must be resource-derived")

    expected = expected_actors or list(DEFAULT_ACTORS)
    actors: dict[str, Any] = manifest.get("actors", {})
    frame_total = 0

    for actor_id in expected:
        actor = actors.get(actor_id)
        if not isinstance(actor, dict):
            _fail(f"missing actor {actor_id}")
        frames = actor.get("frames", [])
        expected_frame_count = int(actor.get("expected_frame_count", -1))
        if expected_frame_count <= 0:
            _fail(f"actor {actor_id} expected_frame_count must be positive")
        if int(actor.get("frame_count", -1)) != expected_frame_count:
            _fail(f"actor {actor_id} frame_count must match expected_frame_count={expected_frame_count}")
        if len(frames) != expected_frame_count:
            _fail(f"actor {actor_id} must have {expected_frame_count} frame records")
        if actor.get("missing_source_members", []):
            _fail(f"actor {actor_id} has missing source members")
        fallback = actor.get("fallback", {})
        if not isinstance(fallback, dict) or not fallback.get("src"):
            _fail(f"actor {actor_id} missing fallback src")

        frames_by_facing: dict[int, list[dict[str, Any]]] = {}
        for frame in frames:
            frames_by_facing.setdefault(int(frame.get("facing_code", -1)), []).append(frame)
        if set(frames_by_facing) != set(range(5)):
            _fail(f"actor {actor_id} must cover source facing codes 0..4")
        for source_group, group_frames in frames_by_facing.items():
            ordered = sorted(group_frames, key=lambda item: int(item.get("pose_index", -1)))
            poses = [int(frame.get("pose_index", -1)) for frame in ordered]
            if poses != list(range(1, len(ordered) + 1)):
                _fail(f"actor {actor_id} facing {source_group} pose indexes must be contiguous from 1")

        animations = actor.get("animations", {})
        idle = animations.get("idle", {}) if isinstance(animations, dict) else {}
        walk = animations.get("walk", {}) if isinstance(animations, dict) else {}
        idle_indexes = [int(frame.get("index", -1)) for frame in frames_by_facing[0]]
        if idle.get("0", {}).get("frames", []) != idle_indexes:
            _fail(f"actor {actor_id} idle frames must match SHAPEDEF source group 0")
        for facing, source_group in {"up": 3, "down": 1, "left": 4, "right": 2}.items():
            walk_entry = walk.get(facing, {})
            expected_indexes = [int(frame.get("index", -1)) for frame in frames_by_facing[source_group]]
            if walk_entry.get("frames", []) != expected_indexes:
                _fail(f"actor {actor_id} walk {facing} must match the SHAPEDEF source group")

        for frame in frames:
            if frame.get("tier") != "resource-derived":
                _fail(f"actor {actor_id} frame {frame.get('index')} must be resource-derived")
            png_path = Path(str(frame.get("png_path", "")))
            if not png_path.exists():
                _fail(f"actor {actor_id} missing PNG {png_path}")
            if not _is_png(png_path):
                _fail(f"actor {actor_id} output is not PNG: {png_path}")
        frame_total += len(frames)

    return {"actor_count": len(expected), "frame_count": frame_total}


class ActorWalkManifestTask(ScriptCheckTask):
    family = 'evidence'

    def __init__(self, tag: str, manifest: str, actors: tuple[str, ...]) -> None:
        self.name = f'actor_walk_manifest:{tag}'
        self.manifest = Path(manifest)
        self.actors = list(actors)
        self.inputs = ()
        self.outputs = (manifest, self.manifest.parent.as_posix() + '/')
        self.replaces = (f'tools/hsl_actor_walk_manifest_check.py {manifest} --actors ' + ' '.join(actors),)
        self.scripts = ('tools/hsltools/evidence/actor_walk_manifest.py',)

    def verify(self, ctx: Context) -> None:
        summary = check_actor_walk_manifest(self.manifest, self.actors)
        print(
            "actor walk manifest ok: actors={} frames={} manifest={}".format(
                summary["actor_count"],
                summary["frame_count"],
                self.manifest,
            )
        )


def tasks() -> list[ActorWalkManifestTask]:
    return [
        ActorWalkManifestTask('chapter01', 'content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json',
                              ('001', '021', '023', '024', '025', '026', '039')),
        ActorWalkManifestTask('shared', 'content/imported/hsl/shared/actor_walk_frames/actor_walk_manifest.json',
                              ('010', '011', '012', '013', '014', '015', '016', '017', '019', '020', '052')),
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--actors", nargs="+", default=list(DEFAULT_ACTORS))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    summary = check_actor_walk_manifest(args.manifest, [str(actor).zfill(3) for actor in args.actors])
    print(
        "actor walk manifest ok: actors={} frames={} manifest={}".format(
            summary["actor_count"],
            summary["frame_count"],
            args.manifest,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
