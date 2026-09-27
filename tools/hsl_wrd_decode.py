#!/usr/bin/env python3
"""Decode a HSL .wrd world file into a compact JSON terrain packet (hsltools.sources.wrd).

Usage:
    python3 tools/hsl_wrd_decode.py path/to/levelXXX.wrd [--output packet.json]

The raw input path is always explicit. Omitting --output prints compact JSON
to stdout; repository data is only replaced by an intentional command.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from hsltools.sources.wrd import decode_wrd


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="path to a raw .wrd file")
    parser.add_argument(
        "--output",
        type=Path,
        help="write JSON to this path; omit to print to stdout",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    wrd_path: Path = args.input
    if not wrd_path.is_file():
        print(f"missing wrd file: {wrd_path}", file=sys.stderr)
        return 2

    data = wrd_path.read_bytes()
    result = decode_wrd(data)
    result["source"] = {
        "basename": wrd_path.name,
        "byte_length": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
        "storage_policy": "raw source stays outside tracked project data",
    }

    text = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.output is not None:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text, encoding="utf-8")
        print(f"PASS wrd_decode: {wrd_path} -> {args.output}")
        stats = result["stats"]
        print(
            f"  {stats['tile_count']} tiles, {stats['blocking_count']} blocking "
            f"({stats['blocking_pct']}%)"
        )
    else:
        print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
