"""TLHS/SHP sprite decoding and PNG preview export.

parse_shp() reads the header and row table and decodes every row (u16 x, u16 count,
RGB565 pixels, 0xffff terminator); write_shp_preview() renders the decoded pixels to
an RGBA PNG through Pillow. Bodies moved verbatim from the former hsl_payload_inspector.py.
"""
from __future__ import annotations

import collections
from pathlib import Path
from typing import Any

SHP_MAGIC = b"TLHS"
SHP_HEADER_SIZE = 0x24
SHP_PIXEL_BYTES = 2
SHP_ROW_TERMINATOR = 0xFFFF


def read_u16le(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 2], "little")


def read_u32le(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def rgb565_to_rgb(value: int) -> tuple[int, int, int]:
    red = ((value >> 11) & 0x1F) * 255 // 31
    green = ((value >> 5) & 0x3F) * 255 // 63
    blue = (value & 0x1F) * 255 // 31
    return red, green, blue


def parse_shp(data: bytes) -> dict[str, Any]:
    if not data.startswith(SHP_MAGIC):
        raise ValueError("not a TLHS/SHP payload")
    width = read_u32le(data, 0x14)
    height = read_u32le(data, 0x18)
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid SHP dimensions: {width}x{height}")

    table_start = SHP_HEADER_SIZE
    pixel_data_start = table_start + height * 4
    offsets = [read_u32le(data, table_start + index * 4) for index in range(height)]
    row_lengths = [
        (offsets[index + 1] if index + 1 < len(offsets) else len(data)) - offset
        for index, offset in enumerate(offsets)
    ]
    decoded_rows = decode_shp_rows(data, width, offsets)
    row_segment_counts = [len(row["segments"]) for row in decoded_rows]
    row_coverages = [row["coverage"] for row in decoded_rows]
    row_decoded = [row["decoded"] for row in decoded_rows]
    flat_pixels = [pixel for row in decoded_rows for pixel in row["pixels"]]
    present_pixels = [pixel for pixel in flat_pixels if pixel is not None]
    header_0x10 = read_u32le(data, 0x10)
    single_full_rows = [
        row["decoded"]
        and len(row["segments"]) == 1
        and row["segments"][0]["x"] == 0
        and row["segments"][0]["count"] == width
        for row in decoded_rows
    ]

    return {
        "kind": "shp_tlhs",
        "magic": "TLHS",
        "byte_length": len(data),
        "u32_0x04": read_u32le(data, 0x04),
        "bytes_per_pixel_candidate": read_u32le(data, 0x08),
        "u32_0x0c": read_u32le(data, 0x0C),
        "color_key_or_flags_0x10": header_0x10,
        "width": width,
        "height": height,
        "u32_0x1c": read_u32le(data, 0x1C),
        "u32_0x20": read_u32le(data, 0x20),
        "row_table_offset": table_start,
        "row_table_entries": len(offsets),
        "pixel_data_start": pixel_data_start,
        "first_row_offset": offsets[0],
        "last_row_offset": offsets[-1],
        "row_encoding_hypothesis": "one or more row segments: u16 x, u16 count, RGB565 pixels, terminated by 0xffff",
        "full_width_single_segment_row_length": width * SHP_PIXEL_BYTES + 6,
        "all_rows_full_width_single_segment": all(single_full_rows),
        "all_rows_decode": all(row_decoded),
        "offsets_monotonic": all(left < right for left, right in zip(offsets, offsets[1:])),
        "first_row_is_after_table": offsets[0] == pixel_data_start,
        "final_row_ends_at_file_size": offsets[-1] + row_lengths[-1] == len(data),
        "row_header_summary": {
            "segment_count_common": [
                {"count": value, "rows": rows}
                for value, rows in collections.Counter(row_segment_counts).most_common(12)
            ],
            "coverage_min": min(row_coverages) if row_coverages else 0,
            "coverage_max": max(row_coverages) if row_coverages else 0,
            "common_coverage": [
                {"pixels": value, "rows": rows}
                for value, rows in collections.Counter(row_coverages).most_common(12)
            ],
        },
        "pixel_value_summary": {
            "present_pixel_count": len(present_pixels),
            "transparent_gap_count": sum(1 for pixel in flat_pixels if pixel is None),
            "top_rgb565_values": [
                {"rgb565_hex": f"0x{value:04x}", "count": count}
                for value, count in collections.Counter(present_pixels).most_common(12)
            ],
            "header_0x10_rgb565_hex": f"0x{header_0x10 & 0xffff:04x}",
            "header_0x10_value_seen_in_pixels": (header_0x10 & 0xffff) in present_pixels,
        },
        "sample_row_lengths": row_lengths[:5],
    }


def decode_shp_rows(data: bytes, width: int, offsets: list[int]) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for row_index, offset in enumerate(offsets):
        end = offsets[row_index + 1] if row_index + 1 < len(offsets) else len(data)
        cursor = offset
        pixels: list[int | None] = [None] * width
        segments: list[dict[str, int]] = []
        decoded = True
        while cursor + 2 <= end:
            marker = read_u16le(data, cursor)
            if marker == SHP_ROW_TERMINATOR:
                cursor += 2
                break
            if cursor + 4 > end:
                decoded = False
                break
            x = marker
            count = read_u16le(data, cursor + 2)
            cursor += 4
            byte_count = count * SHP_PIXEL_BYTES
            if x + count > width or cursor + byte_count > end:
                decoded = False
                break
            for column in range(count):
                pixels[x + column] = read_u16le(data, cursor + column * SHP_PIXEL_BYTES)
            cursor += byte_count
            segments.append({"x": x, "count": count})
        else:
            decoded = False
        if cursor != end:
            decoded = False
        rows.append(
            {
                "decoded": decoded,
                "coverage": sum(1 for pixel in pixels if pixel is not None),
                "segments": segments,
                "pixels": pixels,
            }
        )
    return rows


def shp_pixel_values(data: bytes, shp: dict[str, Any]) -> list[int | None]:
    width = int(shp["width"])
    height = int(shp["height"])
    offsets = [read_u32le(data, SHP_HEADER_SIZE + index * 4) for index in range(height)]
    values: list[int | None] = []
    decoded_rows = decode_shp_rows(data, width, offsets)
    for row in decoded_rows:
        values.extend(row["pixels"])
    return values


def write_shp_preview(data: bytes, shp: dict[str, Any], output_path: Path) -> None:
    """Decode the SHP to an RGBA PNG. An existing file with the same size and pixels is kept
    byte for byte: PNG encoders (Pillow / zlib versions) compress identical pixels
    differently, and the manifests record the file's sha256, so re-encoding would churn
    every tracked frame without changing what the player sees."""
    from PIL import Image

    output_path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (int(shp["width"]), int(shp["height"])))
    image.putdata(
        [
            (*rgb565_to_rgb(value), 255) if value is not None else (0, 0, 0, 0)
            for value in shp_pixel_values(data, shp)
        ]
    )
    if output_path.is_file():
        with Image.open(output_path) as tracked:
            if tracked.size == image.size and tracked.convert("RGBA").tobytes() == image.tobytes():
                return
    image.save(output_path)


def png_sha256(source: Path | bytes) -> str:
    """Pixel hash of a PNG (a path or its bytes): SHA-256 of b'<width>x<height>\\n' + the decoded
    RGBA bytes (palette, tRNS and bit depth normalised by Pillow). The derived manifest's
    `rgba_sha256` and every `png_sha256`-style field a generator embeds for a PNG it wrote: a
    player's Pillow / zlib build encodes the same image to other bytes, and the JSON must still come
    out identical (docs/OPEN_SOURCE_PLAN.md §8.1)."""
    import hashlib
    import io

    from PIL import Image, UnidentifiedImageError
    data = bytes(source) if isinstance(source, (bytes, bytearray)) else Path(source).read_bytes()
    try:
        with Image.open(io.BytesIO(data)) as image:
            rgba = image.convert('RGBA')
            return hashlib.sha256(f'{rgba.width}x{rgba.height}\n'.encode() + rgba.tobytes()).hexdigest()
    except (UnidentifiedImageError, OSError):
        # Not a decodable image: a value no image hashes to, so callers report their own mismatch.
        return 'undecodable:' + hashlib.sha256(data).hexdigest()
