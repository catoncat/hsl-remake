"""PAKS archive reader for the original hsl.pak / movie.pak containers.

Header and LZW-compressed directory decoding (the hsl01.exe LSB-first LZW variant),
record lookup by @:\\path name, record byte extraction and the XOR-0xA8 WAVE members.
Bodies moved verbatim from hsl_resource_scanner.py; the
scanner keeps the signature scanning, extraction and report code.

Typical use:

    packages = find_decoded_paks_packages(ORIGINAL_PAK)
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], '@:\\data\\PLAYERS.TXT'))]
    raw = read_paks_record_bytes(p['path'], r, data_end_offset=int(p['paks']['candidate_index_offset']))
"""
from __future__ import annotations

import hashlib
import re
from pathlib import Path
from typing import Any, BinaryIO

PAKS_MAGIC = b"PAKS"
DEFAULT_READ_SIZE = 4096
XOR_KEY = 0xA8
PAKS_HEADER_SIZE = 0x18
PAKS_DIRECTORY_RECORD_SIZE = 0x2C
PAKS_DIRECTORY_NAME_OFFSET = 0x0C
PAKS_DIRECTORY_NAME_SIZE = 0x20
PAKS_LZW_CLEAR_CODE = 0x100
PAKS_LZW_FIRST_DYNAMIC_CODE = 0x101
PAKS_LZW_MAX_CODE = 0x1FFF


def read_u32le(data: bytes, offset: int) -> int | None:
    if len(data) < offset + 4:
        return None
    return int.from_bytes(data[offset : offset + 4], "little")


def xor_a8(data: bytes) -> bytes:
    return bytes(byte ^ XOR_KEY for byte in data)


def read_xor_a8_u16le(data: bytes, offset: int) -> int | None:
    if len(data) < offset + 2:
        return None
    return int.from_bytes(xor_a8(data[offset : offset + 2]), "little")


def read_xor_a8_u32le(data: bytes, offset: int) -> int | None:
    if len(data) < offset + 4:
        return None
    return int.from_bytes(xor_a8(data[offset : offset + 4]), "little")


def hex_window(data: bytes, offset: int, size: int = 32) -> str:
    if offset >= len(data):
        return ""
    return data[offset : offset + size].hex()


def read_prefix(handle: BinaryIO, size: int = DEFAULT_READ_SIZE) -> bytes:
    handle.seek(0)
    return handle.read(size)


def parse_paks_header(data: bytes) -> dict[str, Any] | None:
    if not data.startswith(PAKS_MAGIC):
        return None

    u32_fields = {
        f"0x{offset:02x}": read_u32le(data, offset)
        for offset in range(0x04, min(len(data), 0x40), 4)
    }
    important_offsets = (0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x20, 0x40, 0x80)

    return {
        "magic": "PAKS",
        "candidate_entry_count": read_u32le(data, 0x04),
        "candidate_size_or_data_offset": read_u32le(data, 0x08),
        "candidate_index_offset": read_u32le(data, 0x08),
        "candidate_constant_0x0c": read_u32le(data, 0x0C),
        "candidate_constant_0x14": read_u32le(data, 0x14),
        "candidate_index_allocation_size": read_u32le(data, 0x14),
        "u32_fields_0x04_to_0x3c": u32_fields,
        "hex_windows": {
            f"0x{offset:02x}": hex_window(data, offset)
            for offset in important_offsets
            if offset < len(data)
        },
    }


def add_paks_derived_fields(paks: dict[str, Any], file_size: int) -> None:
    index_offset = paks.get("candidate_index_offset")
    entry_count = paks.get("candidate_entry_count")
    allocation_size = paks.get("candidate_index_allocation_size")
    if not isinstance(index_offset, int) or index_offset > file_size:
        return

    index_tail_size = file_size - index_offset
    paks["candidate_data_region_offset"] = PAKS_HEADER_SIZE
    paks["candidate_data_region_length"] = max(0, index_offset - PAKS_HEADER_SIZE)
    paks["candidate_index_tail_offset"] = index_offset
    paks["candidate_index_tail_size"] = index_tail_size
    paks["candidate_compressed_index_size"] = index_tail_size
    paks["candidate_trailer_offset"] = index_offset
    paks["candidate_trailer_size"] = index_tail_size
    paks["candidate_index_payload_length"] = index_tail_size
    paks["candidate_directory_record_size"] = PAKS_DIRECTORY_RECORD_SIZE
    if isinstance(allocation_size, int) and allocation_size > 0:
        paks["candidate_directory_capacity"] = allocation_size // PAKS_DIRECTORY_RECORD_SIZE
    if isinstance(entry_count, int) and entry_count > 0:
        paks["candidate_index_payload_bytes_per_entry"] = (
            paks["candidate_index_payload_length"] / entry_count
        )
        paks["candidate_directory_bytes_for_entries"] = entry_count * PAKS_DIRECTORY_RECORD_SIZE


class LsbBitReader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.offset = 0
        self.bit_buffer = 0
        self.bits_left = 0

    def _read_byte(self) -> int | None:
        if self.offset >= len(self.data):
            return None
        value = self.data[self.offset]
        self.offset += 1
        return value

    def read(self, width: int) -> int | None:
        result = 0
        result_shift = 0
        remaining = width
        while remaining > 0:
            if self.bits_left == 0:
                value = self._read_byte()
                if value is None:
                    return None
                self.bit_buffer = value
                self.bits_left = 8
            take = min(remaining, self.bits_left)
            mask = (1 << take) - 1
            result |= (self.bit_buffer & mask) << result_shift
            self.bit_buffer >>= take
            self.bits_left -= take
            result_shift += take
            remaining -= take
        return result


def rebuild_lzw_free_list_after_clear(
    parent: list[int],
    value: list[int],
    ref_count: list[int],
    free_codes: list[int],
) -> int:
    """Rebuild the EXE-style free list for a PAKS LZW clear command."""
    freed = [
        code
        for code in range(PAKS_LZW_FIRST_DYNAMIC_CODE, PAKS_LZW_MAX_CODE + 2)
        if ref_count[code] == 0
    ]
    free_cursor = PAKS_LZW_MAX_CODE + 1
    for code in reversed(freed):
        prefix = parent[code]
        if 0 <= prefix <= PAKS_LZW_MAX_CODE and ref_count[prefix] > 0:
            ref_count[prefix] -= 1
        parent[code] = -1
        value[code] = 0
        ref_count[code] = 0
        free_cursor -= 1
        free_codes[free_cursor - PAKS_LZW_FIRST_DYNAMIC_CODE] = code
    return free_cursor


def decode_lzw_index_block(
    data: bytes,
    output_limit: int,
    trace_events: list[dict[str, int | str]] | None = None,
) -> bytes:
    """Decode the LSB-first LZW-like PAKS index block used by hsl01.exe."""
    if len(data) <= 9:
        return data[:output_limit]

    parent = [-1] * (PAKS_LZW_MAX_CODE + 2)
    value = [0] * (PAKS_LZW_MAX_CODE + 2)
    ref_count = [0] * (PAKS_LZW_MAX_CODE + 2)
    for code in range(0x100):
        value[code] = code
    free_codes = list(range(PAKS_LZW_FIRST_DYNAMIC_CODE, PAKS_LZW_MAX_CODE + 2))
    free_cursor = PAKS_LZW_FIRST_DYNAMIC_CODE
    width = 9
    reader = LsbBitReader(data)
    output = bytearray()

    def output_byte(byte: int) -> None:
        if len(output) >= output_limit:
            raise ValueError("decoded PAKS index exceeds output limit")
        output.append(byte & 0xFF)

    def expand_code(code: int) -> tuple[list[int], int]:
        if not 0 <= code <= PAKS_LZW_MAX_CODE:
            raise ValueError(f"LZW code out of range: 0x{code:x}")
        stack: list[int] = []
        cursor = code
        seen = 0
        while cursor >= PAKS_LZW_FIRST_DYNAMIC_CODE:
            if cursor > PAKS_LZW_MAX_CODE or parent[cursor] == -1:
                raise KeyError(code)
            stack.append(value[cursor] & 0xFF)
            cursor = parent[cursor]
            seen += 1
            if seen > PAKS_LZW_MAX_CODE:
                raise ValueError("cycle in PAKS LZW dictionary")
        first = value[cursor] & 0xFF
        return [first, *reversed(stack)], first

    def add_entry(prefix: int, suffix: int) -> None:
        nonlocal free_cursor
        if free_cursor > PAKS_LZW_MAX_CODE:
            return
        code = free_codes[free_cursor - PAKS_LZW_FIRST_DYNAMIC_CODE]
        free_cursor += 1
        parent[code] = prefix
        value[code] = suffix & 0xFF
        ref_count[code] = 0
        if 0 <= prefix <= PAKS_LZW_MAX_CODE:
            ref_count[prefix] += 1

    def clear_leaf_entries() -> None:
        nonlocal free_cursor
        zero_ref_count = sum(
            1
            for code in range(PAKS_LZW_FIRST_DYNAMIC_CODE, PAKS_LZW_MAX_CODE + 2)
            if ref_count[code] == 0
        )
        old_cursor = free_cursor
        free_cursor = rebuild_lzw_free_list_after_clear(parent, value, ref_count, free_codes)
        if trace_events is not None:
            trace_events.append(
                {
                    "event": "clear",
                    "codes_read": codes_read,
                    "decoded_bytes": len(output),
                    "old_free_cursor": old_cursor,
                    "new_free_cursor": free_cursor,
                    "zero_ref_codes": zero_ref_count,
                }
            )

    first_code = reader.read(width)
    if first_code is None:
        return bytes(output)
    if first_code > 0xFF:
        raise ValueError(f"first PAKS LZW code is not a literal: 0x{first_code:x}")
    old_code = first_code
    old_first = first_code
    output_byte(first_code)
    codes_read = 1
    control_events: list[str] = []

    while True:
        code = reader.read(width)
        codes_read += 1
        if code is None:
            return bytes(output)
        if code == PAKS_LZW_CLEAR_CODE:
            command = reader.read(width)
            codes_read += 1
            if command is None:
                return bytes(output)
            if command == 1:
                width += 1
                if width > 13:
                    raise ValueError("PAKS LZW code width exceeded 13 bits")
                control_events.append(f"code_width={width}@code{codes_read}/out{len(output)}")
                if trace_events is not None:
                    trace_events.append(
                        {
                            "event": "width",
                            "codes_read": codes_read,
                            "decoded_bytes": len(output),
                            "width": width,
                        }
                    )
            elif command == 2:
                clear_leaf_entries()
                control_events.append(f"clear@code{codes_read}/out{len(output)}")
            else:
                raise ValueError(f"unknown PAKS LZW control command: 0x{command:x}")
            control_events = control_events[-8:]
            continue
        if code > PAKS_LZW_MAX_CODE:
            raise ValueError(f"PAKS LZW code out of range: 0x{code:x}")

        try:
            decoded, first = expand_code(code)
        except KeyError:
            try:
                decoded_old, first = expand_code(old_code)
            except KeyError as error:
                controls = ", ".join(control_events) or "none"
                raise ValueError(
                    "PAKS LZW unresolved dictionary state: "
                    f"code=0x{code:x}, old_code=0x{old_code:x}, width={width}, "
                    f"codes_read={codes_read}, decoded_bytes={len(output)}, "
                    f"recent_controls={controls}"
                ) from error
            decoded = decoded_old + [old_first]

        for byte in decoded:
            output_byte(byte)
        add_entry(old_code, first)
        old_code = code
        old_first = first


def parse_paks_directory_records(
    decoded_index: bytes,
    entry_count: int,
    data_end_offset: int | None = None,
) -> list[dict[str, int | str]]:
    records: list[dict[str, int | str]] = []
    max_records = min(entry_count, len(decoded_index) // PAKS_DIRECTORY_RECORD_SIZE)
    for index in range(max_records):
        offset = index * PAKS_DIRECTORY_RECORD_SIZE
        record = decoded_index[offset : offset + PAKS_DIRECTORY_RECORD_SIZE]
        length = read_u32le(record, 0) or 0
        data_offset = read_u32le(record, 4) or 0
        unknown = read_u32le(record, 8) or 0
        raw_name = record[
            PAKS_DIRECTORY_NAME_OFFSET : PAKS_DIRECTORY_NAME_OFFSET + PAKS_DIRECTORY_NAME_SIZE
        ].split(b"\x00", 1)[0]
        name = raw_name.decode("ascii", errors="replace")
        parsed: dict[str, int | str] = {
            "index": index,
            "offset": data_offset,
            "length": length,
            "unknown_0x08": unknown,
            "name": name,
        }
        if data_end_offset is not None:
            parsed["offset_plus_length"] = data_offset + length
            parsed["within_data_region"] = int(
                data_offset >= PAKS_HEADER_SIZE and data_offset + length <= data_end_offset
            )
        records.append(parsed)
    return records


def decode_paks_index(path: Path, paks: dict[str, Any], max_records: int = 200) -> dict[str, Any]:
    index_offset = paks.get("candidate_index_offset")
    entry_count = paks.get("candidate_entry_count")
    output_limit = paks.get("candidate_index_allocation_size")
    if not isinstance(index_offset, int) or not isinstance(entry_count, int):
        return {"status": "skipped", "reason": "missing index offset or entry count"}
    if not isinstance(output_limit, int) or output_limit <= 0:
        return {"status": "skipped", "reason": "missing index allocation size"}

    with path.open("rb") as handle:
        handle.seek(index_offset)
        compressed = handle.read()

    trace_events: list[dict[str, int | str]] = []
    try:
        decoded = decode_lzw_index_block(
            compressed,
            output_limit=output_limit,
            trace_events=trace_events,
        )
        records = parse_paks_directory_records(
            decoded,
            entry_count=entry_count,
            data_end_offset=index_offset,
        )
    except ValueError as error:
        return {
            "status": "failed",
            "compressed_index_offset": index_offset,
            "compressed_index_size": len(compressed),
            "decoded_limit": output_limit,
            "error": str(error),
        }

    named_records = [record for record in records if record.get("name")]
    plausible_records = [
        record
        for record in named_records
        if int(record.get("within_data_region", 0)) == 1 and int(record["length"]) > 0
    ]
    emitted_records = plausible_records if max_records == 0 else plausible_records[:max_records]
    return {
        "status": "decoded",
        "compression": "hsl01.exe LSB-first LZW variant",
        "compressed_index_offset": index_offset,
        "compressed_index_size": len(compressed),
        "decoded_size": len(decoded),
        "decoded_sha256": hashlib.sha256(decoded).hexdigest(),
        "lzw_trace_events": trace_events,
        "record_size": PAKS_DIRECTORY_RECORD_SIZE,
        "entry_count": entry_count,
        "records_parsed": len(records),
        "named_records": len(named_records),
        "plausible_records": len(plausible_records),
        "emitted_records": len(emitted_records),
        "records_truncated": max_records != 0 and len(plausible_records) > max_records,
        "records": emitted_records,
    }


def parse_xor_a8_wave_candidate(path: Path, offset: int, file_size: int) -> dict[str, Any] | None:
    with path.open("rb") as handle:
        handle.seek(offset)
        window = handle.read(128)

    if len(window) < 44:
        return None
    if xor_a8(window[0:4]) != b"RIFF" or xor_a8(window[8:12]) != b"WAVE":
        return None
    if xor_a8(window[12:16]) != b"fmt ":
        return None

    riff_size = read_xor_a8_u32le(window, 4)
    fmt_size = read_xor_a8_u32le(window, 16)
    if riff_size is None or fmt_size is None or fmt_size <= 0:
        return None
    if riff_size <= 8 or offset + 8 + riff_size > file_size:
        return None

    data_marker_offset = 20 + fmt_size
    data_marker_variant = None
    data_chunk_size = None
    if len(window) >= data_marker_offset + 8:
        marker = window[data_marker_offset : data_marker_offset + 4]
        if marker == b"data":
            data_marker_variant = "raw"
        elif marker == b"\xcc\xc9ta":
            data_marker_variant = "xor_a8_da_raw_ta"
        if data_marker_variant:
            data_chunk_size = read_u32le(window, data_marker_offset + 4)

    return {
        "offset": offset,
        "transform": "xor_a8_header",
        "kind": "riff_wave",
        "riff_size": riff_size,
        "candidate_end_offset": offset + 8 + riff_size,
        "fmt_size": fmt_size,
        "audio_format": read_xor_a8_u16le(window, 20),
        "channels": read_xor_a8_u16le(window, 22),
        "sample_rate": read_xor_a8_u32le(window, 24),
        "byte_rate": read_xor_a8_u32le(window, 28),
        "block_align": read_xor_a8_u16le(window, 32),
        "bits_per_sample": read_xor_a8_u16le(window, 34),
        "data_marker_offset": data_marker_offset if data_marker_variant else None,
        "data_marker_variant": data_marker_variant,
        "data_chunk_size": data_chunk_size,
    }


def decoded_xor_a8_wave_bytes(path: Path, candidate: dict[str, Any]) -> bytes:
    offset = int(candidate["offset"])
    end_offset = int(candidate["candidate_end_offset"])
    data_marker_offset = candidate.get("data_marker_offset")
    if not isinstance(data_marker_offset, int):
        raise ValueError(f"candidate has no supported data marker at 0x{offset:x}")

    with path.open("rb") as handle:
        handle.seek(offset)
        raw = bytearray(handle.read(end_offset - offset))

    fmt_size = int(candidate["fmt_size"])
    header_decode_end = 20 + fmt_size
    for index in range(min(header_decode_end, len(raw))):
        raw[index] ^= XOR_KEY

    if len(raw) < data_marker_offset + 8:
        raise ValueError(f"candidate header is truncated at 0x{offset:x}")
    raw[data_marker_offset : data_marker_offset + 4] = b"data"
    return bytes(raw)


def normalize_paks_record_name(name: str) -> str:
    normalized = re.sub(r"[\\/]+", "/", name.strip())
    if len(normalized) >= 2 and normalized[1] == ":":
        drive = normalized[0].lower()
        rest = normalized[2:].lstrip("/")
        return f"{drive}:/{rest.lower()}"
    return normalized.lstrip("/").lower()


def paks_record_lookup_keys(name: str) -> list[str]:
    key = normalize_paks_record_name(name)
    keys = [key]
    if len(key) >= 3 and key[1:3] == ":/":
        keys.append(key[3:])
    return keys


def find_paks_record_by_name(
    records: list[dict[str, int | str]],
    requested_name: str,
) -> dict[str, int | str] | None:
    requested_keys = set(paks_record_lookup_keys(requested_name))
    matches = [
        record
        for record in records
        if requested_keys.intersection(paks_record_lookup_keys(str(record.get("name", ""))))
    ]
    if len(matches) > 1:
        names = ", ".join(str(record.get("name", "")) for record in matches[:5])
        raise ValueError(f"ambiguous PAKS record name {requested_name!r}: {names}")
    return matches[0] if matches else None


def read_decoded_paks_package(path: Path, root: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        first_bytes = read_prefix(handle)
    paks = parse_paks_header(first_bytes)
    if paks is None:
        raise ValueError(f"not a PAKS container: {path}")
    add_paks_derived_fields(paks, path.stat().st_size)
    index = decode_paks_index(path, paks, max_records=0)
    if index.get("status") != "decoded":
        raise ValueError(f"failed to decode PAKS directory for {path}: {index.get('error')}")
    return {
        "path": path,
        "relative_path": path.relative_to(root).as_posix(),
        "paks": paks,
        "paks_index": index,
        "records": index["records"],
    }


def find_decoded_paks_packages(input_root: Path) -> list[dict[str, Any]]:
    if input_root.is_file():
        root = input_root.parent
        candidates = [input_root]
    else:
        root = input_root
        candidates = [
            path
            for path in sorted(input_root.rglob("*"))
            if path.is_file() and path.suffix.lower() == ".pak"
        ]
    packages: list[dict[str, Any]] = []
    for path in candidates:
        with path.open("rb") as handle:
            if handle.read(4) != PAKS_MAGIC:
                continue
        packages.append(read_decoded_paks_package(path, root))
    return packages


def read_paks_record_bytes(
    package_path: Path,
    record: dict[str, int | str],
    data_end_offset: int | None = None,
) -> bytes:
    offset = int(record["offset"])
    length = int(record["length"])
    if offset < PAKS_HEADER_SIZE or length < 0:
        raise ValueError(f"invalid PAKS record bounds: offset=0x{offset:x}, length={length}")
    if data_end_offset is not None and offset + length > data_end_offset:
        raise ValueError(
            "PAKS record extends past data region: "
            f"offset=0x{offset:x}, length={length}, data_end=0x{data_end_offset:x}"
        )
    with package_path.open("rb") as handle:
        handle.seek(offset)
        data = handle.read(length)
    if len(data) != length:
        raise ValueError(f"short read for PAKS record {record.get('name')}: expected {length}, got {len(data)}")
    return data


# Extraction from a PAK writes only under these repository-relative roots (raw records never
# become tracked files by accident).
SAFE_EXTRACT_ROOTS = ("ignored",)


def path_is_relative_to(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def ensure_safe_extract_output(output_root: Path, repo_root: Path | None = None) -> Path:
    repo_root = (repo_root or Path.cwd()).resolve()
    candidate = output_root if output_root.is_absolute() else repo_root / output_root
    resolved = candidate.resolve()
    allowed_roots = [(repo_root / root).resolve() for root in SAFE_EXTRACT_ROOTS]
    if not any(resolved == root or path_is_relative_to(resolved, root) for root in allowed_roots):
        allowed = ", ".join(SAFE_EXTRACT_ROOTS)
        raise SystemExit(f"refusing extraction outside ignored local roots ({allowed}): {output_root}")
    return output_root
