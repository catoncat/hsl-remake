#!/usr/bin/env python3
"""Local-private resource scanner for the user's self-owned HSL archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from hsltools.paths import ORIGINAL_ROOT

from hsltools.sources.pak import (
    PAKS_MAGIC, XOR_KEY, add_paks_derived_fields, decode_paks_index, decoded_xor_a8_wave_bytes,
    ensure_safe_extract_output, find_decoded_paks_packages, find_paks_record_by_name, normalize_paks_record_name,
    parse_paks_header, parse_xor_a8_wave_candidate, read_paks_record_bytes, read_prefix, xor_a8)


DEFAULT_INPUT = ORIGINAL_ROOT
FIRST_CHAPTER_RECORD_NAMES: tuple[str, ...] = (
    "@:\\data\\LEVEL000.BIN",
    "@:\\data\\OBJ-000.OBS",
    "@:\\data\\STORY051.TXT",
    "@:\\data\\winfail051.txt",
    "@:\\magic\\Sp00_001.SHP",
    "@:\\shape\\face0000.shp",
    "@:\\wav\\Accept01.WAV",
    "@:\\wav\\Attack01.WAV",
    "@:\\wav\\Attack02.WAV",
    "@:\\wav\\Attack05.wav",
    "@:\\wav\\Attack06.wav",
)

SIGNATURES: tuple[tuple[str, bytes], ...] = (
    ("pe", b"MZ"),
    ("bmp", b"BM"),
    ("riff", b"RIFF"),
    ("png", b"\x89PNG\r\n\x1a\n"),
    ("jpeg", b"\xff\xd8\xff"),
    ("gif", b"GIF8"),
    ("ogg", b"OggS"),
    ("id3", b"ID3"),
    ("midi", b"MThd"),
    ("zip", b"PK\x03\x04"),
)

XOR_A8_SIGNATURES: tuple[tuple[str, bytes], ...] = tuple(
    (f"xor_a8_{name}", bytes(byte ^ XOR_KEY for byte in signature))
    for name, signature in SIGNATURES
)

RESOURCE_HINT_RE = re.compile(
    rb"(?:[A-Z0-9_./\\-]+\\)?[A-Z0-9_./\\-]+\.(?:SHP|OBS|BIN|WAV|MID|BMP|JPG|AVI|SMK|PAK)",
    re.IGNORECASE,
)


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(chunk_size):
            digest.update(chunk)
    return digest.hexdigest()


def guess_type(first_bytes: bytes) -> str:
    if first_bytes.startswith(PAKS_MAGIC):
        return "paks_container"
    if first_bytes.startswith(b"MZ"):
        return "pe_executable"
    if first_bytes.startswith(b"RIFF"):
        return "riff_media"
    if first_bytes.startswith(b"BM"):
        return "bmp_image"
    if first_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png_image"
    if first_bytes.startswith(b"\xff\xd8\xff"):
        return "jpeg_image"
    if first_bytes.startswith(b"PK\x03\x04"):
        return "zip_archive"
    return "unknown"


def scan_embedded_signatures(data: bytes, max_hits: int = 100) -> list[dict[str, int | str]]:
    hits: list[dict[str, int | str]] = []
    for name, needle in SIGNATURES:
        start = 0
        while len(hits) < max_hits:
            index = data.find(needle, start)
            if index < 0:
                break
            hits.append({"signature": name, "offset": index})
            start = index + 1
    return sorted(hits, key=lambda hit: (int(hit["offset"]), str(hit["signature"])))


def scan_file_for_signatures(
    path: Path,
    max_hits: int = 100,
    chunk_size: int = 1024 * 1024,
    signatures: tuple[tuple[str, bytes], ...] = SIGNATURES,
) -> list[dict[str, int | str]]:
    hits: list[dict[str, int | str]] = []
    max_needle = max(len(needle) for _, needle in signatures)
    offset = 0
    overlap = b""

    with path.open("rb") as handle:
        while len(hits) < max_hits:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            window = overlap + chunk
            window_base = offset - len(overlap)
            for hit in scan_embedded_signatures_with_set(window, signatures, max_hits=max_hits):
                absolute = window_base + int(hit["offset"])
                if absolute >= offset or absolute < offset:
                    candidate = {"signature": hit["signature"], "offset": absolute}
                    if candidate not in hits:
                        hits.append(candidate)
                        if len(hits) >= max_hits:
                            break
            overlap = window[-(max_needle - 1) :]
            offset += len(chunk)

    return sorted(hits, key=lambda hit: (int(hit["offset"]), str(hit["signature"])))


def scan_embedded_signatures_with_set(
    data: bytes,
    signatures: tuple[tuple[str, bytes], ...],
    max_hits: int = 100,
) -> list[dict[str, int | str]]:
    hits: list[dict[str, int | str]] = []
    for name, needle in signatures:
        start = 0
        while len(hits) < max_hits:
            index = data.find(needle, start)
            if index < 0:
                break
            hits.append({"signature": name, "offset": index})
            start = index + 1
    return sorted(hits, key=lambda hit: (int(hit["offset"]), str(hit["signature"])))


def find_file_offsets(
    path: Path,
    needle: bytes,
    max_hits: int = 100,
    chunk_size: int = 1024 * 1024,
) -> list[int]:
    offsets: list[int] = []
    overlap = b""
    offset = 0
    with path.open("rb") as handle:
        while len(offsets) < max_hits:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            window = overlap + chunk
            window_base = offset - len(overlap)
            start = 0
            while len(offsets) < max_hits:
                index = window.find(needle, start)
                if index < 0:
                    break
                absolute = window_base + index
                if absolute >= offset or absolute < offset:
                    offsets.append(absolute)
                start = index + 1
            overlap = window[-(len(needle) - 1) :]
            offset += len(chunk)
    return offsets


def scan_xor_a8_wave_candidates(path: Path, max_hits: int = 100) -> list[dict[str, Any]]:
    offsets = find_file_offsets(path, xor_a8(b"RIFF"), max_hits=max_hits)
    file_size = path.stat().st_size
    candidates = [
        candidate
        for offset in offsets
        if (candidate := parse_xor_a8_wave_candidate(path, offset, file_size)) is not None
    ]
    for index, candidate in enumerate(candidates[:-1]):
        candidate["contiguous_with_next_candidate"] = (
            candidate["candidate_end_offset"] == candidates[index + 1]["offset"]
        )
    if candidates:
        candidates[-1]["contiguous_with_next_candidate"] = None
    return candidates


def safe_output_component(component: str) -> str:
    if component in {"", ".", ".."}:
        raise ValueError(f"unsafe empty or relative record path component: {component!r}")
    safe = re.sub(r"[^A-Za-z0-9._-]+", "_", component)
    if safe in {"", ".", ".."}:
        raise ValueError(f"unsafe record path component after normalization: {component!r}")
    return safe


def paks_record_output_relative_path(package_relative_path: str, record_name: str) -> Path:
    package_stem = safe_output_component(Path(package_relative_path).stem)
    normalized = re.sub(r"[\\/]+", "/", record_name.strip())
    drive_label = "drive_none"
    rest = normalized.lstrip("/")
    if len(normalized) >= 2 and normalized[1] == ":":
        drive = normalized[0]
        drive_label = {
            "@": "drive_at",
            "?": "drive_question",
        }.get(drive, f"drive_{safe_output_component(drive.lower())}")
        rest = normalized[2:].lstrip("/")
    components = [safe_output_component(part) for part in rest.split("/") if part]
    if not components:
        raise ValueError(f"PAKS record has no output path components: {record_name!r}")
    return Path(package_stem, drive_label, *components)


def paks_record_category(record_name: str) -> str:
    key = normalize_paks_record_name(record_name)
    if len(key) >= 3 and key[1:3] == ":/":
        key = key[3:]
    namespace, _, basename = key.partition("/")
    if namespace == "data":
        stem = basename.rsplit("/", 1)[-1]
        if stem.startswith("story"):
            return "story"
        if stem.startswith("winfail"):
            return "winfail"
        return "data"
    if namespace in {"magic", "shape", "wav", "movie"}:
        return namespace
    return namespace or "unknown"


def extract_named_paks_records(
    input_root: Path,
    output_root: Path,
    record_names: list[str],
    import_manifest_path: Path | None = None,
) -> dict[str, Any]:
    output_root = ensure_safe_extract_output(output_root)
    if import_manifest_path is not None:
        ensure_safe_extract_output(import_manifest_path.parent)
    output_root.mkdir(parents=True, exist_ok=True)

    packages = find_decoded_paks_packages(input_root)
    if not packages:
        raise SystemExit(f"no PAKS containers found under {input_root}")

    extracted: list[dict[str, Any]] = []
    for requested_name in record_names:
        matches: list[tuple[dict[str, Any], dict[str, int | str]]] = []
        for package in packages:
            record = find_paks_record_by_name(package["records"], requested_name)
            if record is not None:
                matches.append((package, record))
        if not matches:
            raise SystemExit(f"PAKS record not found by decoded name: {requested_name}")
        if len(matches) > 1:
            sources = ", ".join(package["relative_path"] for package, _ in matches)
            raise SystemExit(f"ambiguous decoded PAKS record {requested_name!r} in {sources}")

        package, record = matches[0]
        relative_output = paks_record_output_relative_path(
            package["relative_path"],
            str(record["name"]),
        )
        output_path = output_root / relative_output
        output_path.parent.mkdir(parents=True, exist_ok=True)

        data = read_paks_record_bytes(
            package["path"],
            record,
            data_end_offset=int(package["paks"]["candidate_index_offset"]),
        )
        output_path.write_bytes(data)
        digest = hashlib.sha256(data).hexdigest()
        output_size = output_path.stat().st_size
        extracted.append(
            {
                "source_package_path": package["path"].as_posix(),
                "source_package_relative_path": package["relative_path"],
                "decoded_record_name": record["name"],
                "requested_record_name": requested_name,
                "normalized_lookup_key": normalize_paks_record_name(str(record["name"])),
                "index": record["index"],
                "offset": record["offset"],
                "offset_hex": f"0x{int(record['offset']):x}",
                "length": record["length"],
                "sha256": digest,
                "output_path": output_path.as_posix(),
                "output_relative_path": relative_output.as_posix(),
                "category": paks_record_category(str(record["name"])),
                "output_size": output_size,
                "output_length_matches_record_length": output_size == int(record["length"]),
            }
        )

    import_manifest = {
        "input_root": input_root.as_posix(),
        "output_root": output_root.as_posix(),
        "payload_policy": "local-private ignored output; do not commit, publish, upload, or share",
        "extraction": "exact PAKS record byte ranges by decoded directory name; payload formats not decoded",
        "target_record_names": record_names,
        "record_count": len(extracted),
        "all_output_lengths_match_record_lengths": all(
            item["output_length_matches_record_length"] for item in extracted
        ),
        "records": extracted,
    }
    if import_manifest_path is not None:
        import_manifest_path.parent.mkdir(parents=True, exist_ok=True)
        import_manifest_path.write_text(
            json.dumps(import_manifest, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        import_manifest["import_manifest_path"] = import_manifest_path.as_posix()
    return import_manifest


def extract_xor_a8_waves(
    manifest: dict[str, Any],
    input_root: Path,
    output_root: Path,
    limit_per_file: int,
) -> dict[str, Any]:
    ensure_safe_extract_output(output_root)
    output_root.mkdir(parents=True, exist_ok=True)

    extracted: list[dict[str, Any]] = []
    for item in manifest["files"]:
        candidates = item.get("xor_a8_wave_candidates") or []
        if not candidates:
            continue
        source_path = input_root / item["relative_path"]
        source_stem = Path(item["relative_path"]).stem
        source_dir = output_root / source_stem
        source_dir.mkdir(parents=True, exist_ok=True)

        for index, candidate in enumerate(candidates[:limit_per_file]):
            try:
                decoded = decoded_xor_a8_wave_bytes(source_path, candidate)
            except ValueError as error:
                extracted.append(
                    {
                        "source": item["relative_path"],
                        "candidate_index": index,
                        "offset": candidate["offset"],
                        "status": "skipped",
                        "reason": str(error),
                    }
                )
                continue

            output_path = source_dir / f"{source_stem}_xor_a8_wave_{index:04d}_0x{int(candidate['offset']):x}.wav"
            output_path.write_bytes(decoded)
            extracted.append(
                {
                    "source": item["relative_path"],
                    "candidate_index": index,
                    "offset": candidate["offset"],
                    "candidate_end_offset": candidate["candidate_end_offset"],
                    "output": output_path.as_posix(),
                    "size": output_path.stat().st_size,
                    "sha256": sha256_file(output_path),
                    "sample_rate": candidate.get("sample_rate"),
                    "bits_per_sample": candidate.get("bits_per_sample"),
                    "channels": candidate.get("channels"),
                    "status": "extracted",
                }
            )

    extract_manifest = {
        "input_root": input_root.as_posix(),
        "output_root": output_root.as_posix(),
        "transform": "xor_a8_header_to_standard_wave",
        "payload_policy": "local-private ignored output; do not commit or publish",
        "extracted_count": sum(1 for item in extracted if item["status"] == "extracted"),
        "items": extracted,
    }
    manifest_path = output_root / "xor-a8-wave-extract-manifest.json"
    manifest_path.write_text(
        json.dumps(extract_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return extract_manifest


def find_resource_string_hints(data: bytes, max_hints: int = 100) -> list[str]:
    seen: set[str] = set()
    hints: list[str] = []
    for match in RESOURCE_HINT_RE.finditer(data):
        value = match.group(0).decode("ascii", errors="ignore")
        if value in seen:
            continue
        seen.add(value)
        hints.append(value)
        if len(hints) >= max_hints:
            break
    return hints


def find_resource_string_hint_hits(data: bytes, base_offset: int = 0) -> list[dict[str, int | str]]:
    return [
        {
            "value": match.group(0).decode("ascii", errors="ignore"),
            "offset": base_offset + match.start(),
        }
        for match in RESOURCE_HINT_RE.finditer(data)
    ]


def scan_resource_string_hints(
    path: Path,
    max_hints: int = 100,
    max_bytes: int = 4 * 1024 * 1024,
) -> list[str]:
    with path.open("rb") as handle:
        return find_resource_string_hints(handle.read(max_bytes), max_hints=max_hints)


def scan_resource_string_hint_hits(
    path: Path,
    max_hints: int = 100,
    chunk_size: int = 1024 * 1024,
) -> list[dict[str, int | str]]:
    seen: set[str] = set()
    hits: list[dict[str, int | str]] = []
    overlap = b""
    offset = 0

    with path.open("rb") as handle:
        while len(hits) < max_hints:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            window = overlap + chunk
            window_base = offset - len(overlap)
            for hit in find_resource_string_hint_hits(window, base_offset=window_base):
                value = str(hit["value"])
                absolute = int(hit["offset"])
                if absolute < offset and overlap:
                    continue
                if value in seen:
                    continue
                seen.add(value)
                hits.append(hit)
                if len(hits) >= max_hints:
                    break
            overlap = window[-256:]
            offset += len(chunk)
    return hits


def scan_file(
    path: Path,
    root: Path,
    max_signature_hits: int = 100,
    max_wave_candidates: int = 100,
    max_resource_hints: int = 100,
    max_index_records: int = 200,
) -> dict[str, Any]:
    with path.open("rb") as handle:
        first_bytes = read_prefix(handle)

    item: dict[str, Any] = {
        "relative_path": path.relative_to(root).as_posix(),
        "size": path.stat().st_size,
        "sha256": sha256_file(path),
        "first_bytes_hex": first_bytes[:32].hex(),
        "guessed_type": guess_type(first_bytes),
        "signature_hits": scan_file_for_signatures(path, max_hits=max_signature_hits),
        "xor_a8_signature_hits": scan_file_for_signatures(
            path,
            max_hits=max_signature_hits,
            signatures=XOR_A8_SIGNATURES,
        ),
    }

    paks = parse_paks_header(first_bytes)
    if paks is not None:
        add_paks_derived_fields(paks, item["size"])
        item["xor_a8_wave_candidates"] = scan_xor_a8_wave_candidates(
            path,
            max_hits=max_wave_candidates,
        )
        item["paks"] = paks
        item["paks_index"] = decode_paks_index(path, paks, max_records=max_index_records)

    hint_hits = scan_resource_string_hint_hits(path, max_hints=max_resource_hints)
    if hint_hits:
        item["resource_string_hint_hits"] = hint_hits
        item["resource_string_hints"] = [str(hit["value"]) for hit in hint_hits]

    return item


def scan_directory(
    root: Path | str,
    max_signature_hits: int = 100,
    max_wave_candidates: int = 100,
    max_resource_hints: int = 100,
    max_index_records: int = 200,
) -> dict[str, Any]:
    root_path = Path(root)
    files = [
        scan_file(
            path,
            root_path,
            max_signature_hits=max_signature_hits,
            max_wave_candidates=max_wave_candidates,
            max_resource_hints=max_resource_hints,
            max_index_records=max_index_records,
        )
        for path in sorted(root_path.rglob("*"))
        if path.is_file()
    ]
    return {
        "input_root": root_path.as_posix(),
        "file_count": len(files),
        "files": files,
    }


def write_json(manifest: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def write_markdown(manifest: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# HSL Local Resource Scan",
        "",
        f"input_root: `{manifest['input_root']}`",
        f"file_count: {manifest['file_count']}",
        "",
        "## Files",
        "",
        "| file | size | sha256 | type |",
        "| --- | ---: | --- | --- |",
    ]
    for item in manifest["files"]:
        lines.append(
            f"| `{item['relative_path']}` | {item['size']} | `{item['sha256']}` | {item['guessed_type']} |"
        )

    paks_files = [item for item in manifest["files"] if "paks" in item]
    if paks_files:
        lines.extend(
            [
                "",
                "## PAKS Containers",
                "",
                "| file | entries? | data offset | data length | index offset | index tail size | record size | capacity | 0x0c | 0x14 |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            ]
        )
        for item in paks_files:
            paks = item["paks"]
            lines.append(
                "| `{}` | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
                    item["relative_path"],
                    paks["candidate_entry_count"],
                    paks.get("candidate_data_region_offset", "unknown"),
                    paks.get("candidate_data_region_length", "unknown"),
                    paks.get("candidate_index_offset", "unknown"),
                    paks.get("candidate_index_tail_size", "unknown"),
                    paks.get("candidate_directory_record_size", "unknown"),
                    paks.get("candidate_directory_capacity", "unknown"),
                    paks["candidate_constant_0x0c"],
                    paks["candidate_constant_0x14"],
                )
            )

        lines.extend(["", "## Decoded PAKS Index Candidates", ""])
        for item in paks_files:
            index = item.get("paks_index") or {}
            lines.append(
                "- `{}`: status `{}`, decoded_size `{}`, plausible_records `{}`, emitted_records `{}`".format(
                    item["relative_path"],
                    index.get("status", "unknown"),
                    index.get("decoded_size", "unknown"),
                    index.get("plausible_records", "unknown"),
                    index.get("emitted_records", "unknown"),
                )
            )
            for record in (index.get("records") or [])[:20]:
                lines.append(
                    "  - `{name}` offset `0x{offset:x}` length `{length}` unknown_0x08 `0x{unknown:x}`".format(
                        name=record.get("name", ""),
                        offset=int(record.get("offset", 0)),
                        length=int(record.get("length", 0)),
                        unknown=int(record.get("unknown_0x08", 0)),
                    )
                )
            if index.get("records_truncated"):
                lines.append("  - truncated: use `--max-index-records 0` for all plausible records")

        lines.extend(["", "## XOR A8 RIFF/WAVE Candidates", ""])
        for item in paks_files:
            candidates = item.get("xor_a8_wave_candidates", [])
            lines.append(f"- `{item['relative_path']}`: {len(candidates)} candidate(s) captured")
            for candidate in candidates[:20]:
                lines.append(
                    "  - offset `0x{offset:x}`, end `0x{end:x}`, sample_rate `{rate}`, "
                    "bits `{bits}`, data_marker `{marker}`, contiguous_next `{contiguous}`".format(
                        offset=candidate["offset"],
                        end=candidate["candidate_end_offset"],
                        rate=candidate.get("sample_rate"),
                        bits=candidate.get("bits_per_sample"),
                        marker=candidate.get("data_marker_variant"),
                        contiguous=candidate.get("contiguous_with_next_candidate"),
                    )
                )
            if len(candidates) > 20:
                lines.append(f"  - truncated: {len(candidates)} total candidates in manifest")

    lines.extend(
        [
            "",
            "## Signature Hits",
            "",
            "Offsets are byte offsets only; payload bytes are not exported.",
            "",
        ]
    )
    for item in manifest["files"]:
        hits = item["signature_hits"]
        hit_text = ", ".join(f"{hit['signature']}@0x{int(hit['offset']):x}" for hit in hits[:20])
        if len(hits) > 20:
            hit_text += f", ... ({len(hits)} total)"
        lines.append(f"- `{item['relative_path']}`: {hit_text or 'none'}")

    hint_files = [item for item in manifest["files"] if item.get("resource_string_hints")]
    if hint_files:
        lines.extend(["", "## Resource String Hints", ""])
        for item in hint_files:
            hits = item.get("resource_string_hint_hits") or []
            hint_text = ", ".join(
                f"`{hit['value']}`@0x{int(hit['offset']):x}" for hit in hits[:30]
            )
            lines.append(f"- `{item['relative_path']}`: {hint_text}")
            if len(hits) > 30:
                lines.append(f"  - truncated: {len(hits)} total hints")

    output.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", default=DEFAULT_INPUT, type=Path)
    parser.add_argument("--json", dest="json_output", type=Path)
    parser.add_argument("--markdown", dest="markdown_output", type=Path)
    parser.add_argument("--max-signature-hits", default=100, type=int)
    parser.add_argument("--max-wave-candidates", default=100, type=int)
    parser.add_argument("--max-resource-hints", default=100, type=int)
    parser.add_argument(
        "--max-index-records",
        default=200,
        type=int,
        help="maximum decoded PAKS index records to emit; use 0 for all plausible records",
    )
    parser.add_argument(
        "--extract-xor-a8-waves",
        dest="extract_xor_a8_waves",
        type=Path,
        help="write decoded local-private WAV candidates to an ignored output root",
    )
    parser.add_argument("--extract-limit-per-file", default=20, type=int)
    parser.add_argument(
        "--extract-paks-records",
        dest="extract_paks_records",
        type=Path,
        help="write exact decoded PAKS record byte ranges under an ignored output root",
    )
    parser.add_argument(
        "--extract-paks-record",
        dest="extract_paks_record_names",
        action="append",
        default=[],
        help="decoded PAKS record name to extract; may be repeated",
    )
    parser.add_argument(
        "--extract-first-chapter-records",
        action="store_true",
        help="extract the current first-chapter candidate record list",
    )
    parser.add_argument(
        "--extract-paks-import-manifest",
        dest="extract_paks_import_manifest",
        type=Path,
        help="write an ignored import manifest for extracted PAKS records",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.input.exists():
        raise SystemExit(f"input path does not exist: {args.input}")

    needs_scan = (
        args.json_output
        or args.markdown_output
        or args.extract_xor_a8_waves
        or not args.extract_paks_records
    )
    manifest: dict[str, Any] | None = None
    if needs_scan:
        manifest = scan_directory(
            args.input,
            max_signature_hits=args.max_signature_hits,
            max_wave_candidates=args.max_wave_candidates,
            max_resource_hints=args.max_resource_hints,
            max_index_records=args.max_index_records,
        )
        if args.json_output:
            write_json(manifest, args.json_output)
        if args.markdown_output:
            write_markdown(manifest, args.markdown_output)
        if args.extract_xor_a8_waves:
            extract_manifest = extract_xor_a8_waves(
                manifest,
                args.input,
                args.extract_xor_a8_waves,
                args.extract_limit_per_file,
            )
            print(
                "extracted {} local-private WAV candidate(s) under {}".format(
                    extract_manifest["extracted_count"],
                    args.extract_xor_a8_waves,
                )
            )

    paks_record_names = list(args.extract_paks_record_names)
    if args.extract_first_chapter_records:
        paks_record_names.extend(FIRST_CHAPTER_RECORD_NAMES)
    paks_record_names = list(dict.fromkeys(paks_record_names))
    if args.extract_paks_import_manifest and not args.extract_paks_records:
        raise SystemExit("--extract-paks-import-manifest requires --extract-paks-records")
    if args.extract_paks_records:
        if not paks_record_names:
            raise SystemExit(
                "--extract-paks-records requires --extract-paks-record or "
                "--extract-first-chapter-records"
            )
        paks_manifest = extract_named_paks_records(
            args.input,
            args.extract_paks_records,
            paks_record_names,
            import_manifest_path=args.extract_paks_import_manifest,
        )
        print(
            "extracted {} exact PAKS record(s) under {}".format(
                paks_manifest["record_count"],
                args.extract_paks_records,
            )
        )

    if (
        manifest is not None
        and not args.json_output
        and not args.markdown_output
        and not args.extract_xor_a8_waves
        and not args.extract_paks_records
    ):
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
