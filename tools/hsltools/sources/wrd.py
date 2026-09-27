"""Decode a HSL .wrd world file into the compact terrain packet (hsl_wrd_terrain.v2).

The WRD format (static-derived from level051.wrd):
  Header (24 bytes):
    magic    : 4s  = "WORL"
    version  : u32
    flags    : u32
    width    : u32
    height   : u32
    esize    : u32  (element size in bytes, observed = 4)
  Data (width * height * esize bytes):
    Each entry is a little-endian u32:
      bits  0..23 = tile_id (index into tileset)
      bits 24..31 = source height attribute (0xff is a ground cliff)

Evidence tier: resource-derived. Ground/flying costs are checked separately against the
original flood. Keep height bytes instead of collapsing to a bool. The battle seed and
hsltools.data.terrain_heights decode through this one function; the command line is
tools/hsl_wrd_decode.py. Body moved verbatim from that script.
"""
from __future__ import annotations

import struct

HEADER_FMT = "<4s5I"
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 24


def decode_wrd(data: bytes) -> dict:
    if len(data) < HEADER_SIZE:
        raise ValueError(f"file too small: {len(data)} bytes")
    magic, version, flags, width, height, esize = struct.unpack_from(HEADER_FMT, data, 0)
    if magic != b"WORL":
        raise ValueError(f"bad magic: {magic!r}")
    if esize != 4:
        raise ValueError(f"unsupported element_size={esize} (expected 4)")
    if not 0 < width <= 256 or not 0 < height <= 256:
        raise ValueError("unsupported terrain dimensions")
    expected = width * height * esize
    body = data[HEADER_SIZE:]
    if len(body) < expected:
        raise ValueError(f"body too small: {len(body)} < {expected}")
    grid: list[list[dict]] = []
    blocking = 0
    tile_ids: set[int] = set()
    for row in range(height):
        r: list[dict] = []
        for col in range(width):
            off = (row * width + col) * esize
            val = struct.unpack_from("<I", body, off)[0]
            tile_id = val & 0xFFFFFF
            attr = (val >> 24) & 0xFF
            is_blocking = attr == 0xFF
            if is_blocking:
                blocking += 1
            tile_ids.add(tile_id)
            r.append({"t": tile_id, "b": 1 if is_blocking else 0, "h": attr})
        grid.append(r)
    return {
        "schema": "hsl_wrd_terrain.v2",
        "evidence_tier": "resource-derived",
        "source_format": {
            "magic": "WORL",
            "version": version,
            "flags": flags,
            "width": width,
            "height": height,
            "element_size": esize,
            "entry_encoding": "u32 LE: bits 0-23=tile_id, bits 24-31=source height; b records h==255",
        },
        "stats": {
            "tile_count": width * height,
            "blocking_count": blocking,
            "blocking_pct": round(blocking / (width * height) * 100, 1),
            "unique_tile_count": len(tile_ids),
            "tile_id_min": min(tile_ids),
            "tile_id_max": max(tile_ids),
        },
        "grid": grid,
        "unresolved_semantics": [
            "Whole native map-flag lifecycle and large-body traversal remain separate.",
            "Equal-cost path ties are a remake policy; source ground/flying costs are independently checked.",
        ],
    }
