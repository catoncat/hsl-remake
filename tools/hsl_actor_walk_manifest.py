#!/usr/bin/env python3
"""Build actor walk-frame PNGs and a manifest from local HSL PAK records (hsltools.sources.actor_walk_frames)."""

from __future__ import annotations

import argparse
from pathlib import Path

from hsltools.sources.actor_walk_frames import (
    DEFAULT_ACTORS,
    DEFAULT_INPUT,
    DEFAULT_OUTPUT_ROOT,
    DEFAULT_RES_ROOT,
    build_actor_walk_manifest,
    collect_actor_walk_records,
    write_manifest,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="hsl.pak path or directory containing PAK files")
    parser.add_argument("--actors", nargs="+", default=list(DEFAULT_ACTORS), help="actor ids to extract, e.g. 001 021")
    parser.add_argument("--output-root", type=Path, default=DEFAULT_OUTPUT_ROOT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_OUTPUT_ROOT / "actor_walk_manifest.json")
    parser.add_argument("--res-root", default=DEFAULT_RES_ROOT)
    parser.add_argument("--no-decode-png", action="store_true", help="build manifest paths without writing PNG previews")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    actor_ids = [str(actor).zfill(3) for actor in args.actors]
    records = collect_actor_walk_records(args.input, actor_ids)
    manifest = build_actor_walk_manifest(
        actor_ids,
        records,
        args.output_root,
        decode_png=not args.no_decode_png,
        res_root=args.res_root,
    )
    write_manifest(manifest, args.manifest)
    print(
        "actor walk manifest ok: actors={} frames={} manifest={}".format(
            len(actor_ids),
            sum(int(actor.get("frame_count", 0)) for actor in manifest["actors"].values()),
            args.manifest,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
