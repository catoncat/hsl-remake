import json
import tempfile
import unittest
from pathlib import Path

from hsltools.sources.pak import (
    PAKS_MAGIC,
    XOR_KEY,
    add_paks_derived_fields,
    decoded_xor_a8_wave_bytes,
    decode_lzw_index_block,
    ensure_safe_extract_output,
    find_paks_record_by_name,
    normalize_paks_record_name,
    parse_paks_directory_records,
    parse_paks_header,
    paks_record_lookup_keys,
    read_paks_record_bytes,
    rebuild_lzw_free_list_after_clear,
)
from tools.hsl_resource_scanner import (
    guess_type,
    paks_record_category,
    paks_record_output_relative_path,
    scan_directory,
    scan_embedded_signatures,
    find_resource_string_hints,
    scan_xor_a8_wave_candidates,
)


class ResourceScannerTests(unittest.TestCase):
    def pack_lsb_codes(self, codes: list[int], width: int = 9) -> bytes:
        accumulator = 0
        bit_count = 0
        output = bytearray()
        for code in codes:
            accumulator |= code << bit_count
            bit_count += width
            while bit_count >= 8:
                output.append(accumulator & 0xFF)
                accumulator >>= 8
                bit_count -= 8
        if bit_count:
            output.append(accumulator & 0xFF)
        return bytes(output)

    def build_xor_a8_wave(self, sample_data: bytes) -> bytes:
        def xored(value: bytes) -> bytes:
            return bytes(byte ^ XOR_KEY for byte in value)

        fmt_payload = (
            (1).to_bytes(2, "little")
            + (1).to_bytes(2, "little")
            + (16000).to_bytes(4, "little")
            + (32000).to_bytes(4, "little")
            + (2).to_bytes(2, "little")
            + (16).to_bytes(2, "little")
            + (0).to_bytes(2, "little")
        )
        riff_size = 4 + 8 + len(fmt_payload) + 8 + len(sample_data)
        return (
            xored(b"RIFF")
            + xored(riff_size.to_bytes(4, "little"))
            + xored(b"WAVE")
            + xored(b"fmt ")
            + xored(len(fmt_payload).to_bytes(4, "little"))
            + xored(fmt_payload)
            + b"data"
            + len(sample_data).to_bytes(4, "little")
            + sample_data
        )

    def test_scan_directory_reports_file_metadata_and_paks_fields(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pak = root / "sample.pak"
            wave = self.build_xor_a8_wave(b"\x00\x01\x02\x03")
            index_offset = 0x18 + len(wave)
            compressed_index_tail = b"compressed-index"
            pak.write_bytes(
                PAKS_MAGIC
                + (2).to_bytes(4, "little")
                + index_offset.to_bytes(4, "little")
                + (0x403F).to_bytes(4, "little")
                + b"\x00\x00\x00\x00"
                + (0x00055F00).to_bytes(4, "little")
                + wave
                + compressed_index_tail
            )

            manifest = scan_directory(root)

        self.assertEqual(len(manifest["files"]), 1)
        item = manifest["files"][0]
        self.assertEqual(item["relative_path"], "sample.pak")
        self.assertEqual(item["guessed_type"], "paks_container")
        self.assertEqual(item["paks"]["magic"], "PAKS")
        self.assertEqual(item["paks"]["candidate_entry_count"], 2)
        self.assertEqual(item["paks"]["candidate_index_offset"], index_offset)
        self.assertEqual(item["paks"]["candidate_data_region_offset"], 0x18)
        self.assertEqual(item["paks"]["candidate_data_region_length"], len(wave))
        self.assertEqual(item["paks"]["candidate_index_tail_size"], len(compressed_index_tail))
        self.assertEqual(item["paks"]["candidate_directory_record_size"], 0x2C)
        self.assertEqual(item["paks"]["candidate_directory_capacity"], 8000)
        self.assertEqual(item["xor_a8_signature_hits"][0]["signature"], "xor_a8_riff")
        self.assertEqual(len(item["xor_a8_wave_candidates"]), 1)
        self.assertEqual(item["xor_a8_wave_candidates"][0]["sample_rate"], 16000)
        self.assertEqual(item["xor_a8_wave_candidates"][0]["data_marker_variant"], "raw")

    def test_paks_record_name_normalization_and_output_path(self):
        self.assertEqual(
            normalize_paks_record_name("@:\\DATA\\Level000.BIN"),
            "@:/data/level000.bin",
        )
        self.assertEqual(
            paks_record_lookup_keys("@:\\DATA\\Level000.BIN"),
            ["@:/data/level000.bin", "data/level000.bin"],
        )
        self.assertEqual(
            paks_record_output_relative_path(
                "hsl.pak",
                "@:\\data\\LEVEL000.BIN",
            ).as_posix(),
            "hsl/drive_at/data/LEVEL000.BIN",
        )
        self.assertEqual(paks_record_category("@:\\data\\STORY051.TXT"), "story")
        self.assertEqual(paks_record_category("@:\\data\\winfail051.txt"), "winfail")
        self.assertEqual(paks_record_category("@:\\magic\\Sp00_001.SHP"), "magic")

        record = find_paks_record_by_name(
            [{"name": "@:\\data\\LEVEL000.BIN", "offset": 0x18, "length": 640}],
            "data/level000.bin",
        )

        self.assertIsNotNone(record)
        self.assertEqual(record["name"], "@:\\data\\LEVEL000.BIN")

    def test_safe_extract_output_rejects_paths_outside_ignored_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)

            self.assertEqual(
                ensure_safe_extract_output(Path("ignored/extracts/first-chapter"), repo_root=repo),
                Path("ignored/extracts/first-chapter"),
            )
            with self.assertRaises(SystemExit):
                ensure_safe_extract_output(Path("ignored/../outside"), repo_root=repo)
            with self.assertRaises(SystemExit):
                ensure_safe_extract_output(repo / "asset-dumps/reports", repo_root=repo)
            with self.assertRaises(SystemExit):
                ensure_safe_extract_output(Path("legal-assets/derived/first-chapter"), repo_root=repo)
            with self.assertRaises(SystemExit):
                ensure_safe_extract_output(Path("/tmp/hsl-first-chapter-outside"), repo_root=repo)

    def test_read_paks_record_bytes_uses_record_range_bounds(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "sample.pak"
            source.write_bytes(b"\x00" * 0x18 + b"payload" + b"tail")
            record = {"name": "@:\\data\\LEVEL000.BIN", "offset": 0x18, "length": 7}

            self.assertEqual(
                read_paks_record_bytes(source, record, data_end_offset=0x18 + 7),
                b"payload",
            )
            with self.assertRaises(ValueError):
                read_paks_record_bytes(source, record, data_end_offset=0x18 + 6)

    def test_lzw_index_decoder_expands_literal_codes(self):
        expected = b"ABCDEFGHIJK"
        compressed = self.pack_lsb_codes(list(expected))

        decoded = decode_lzw_index_block(compressed, output_limit=16)

        self.assertEqual(decoded, expected)

    def test_lzw_index_decoder_reuses_leaf_codes_after_clear_command(self):
        compressed = self.pack_lsb_codes(
            [
                ord("A"),
                ord("B"),
                ord("C"),
                ord("D"),
                0x100,
                0x02,
                ord("E"),
                0x101,
                ord("F"),
                ord("G"),
            ]
        )

        decoded = decode_lzw_index_block(compressed, output_limit=16)

        self.assertEqual(decoded, b"ABCDEDEFG")

    def test_lzw_clear_does_not_cascade_free_new_zero_ref_parents(self):
        parent = [-1] * (0x2001)
        value = [0] * (0x2001)
        ref_count = [0] * (0x2001)
        free_codes = list(range(0x101, 0x2001))
        parent[0x102] = 0x104
        value[0x102] = ord("x")
        parent[0x104] = ord("A")
        value[0x104] = ord("y")
        ref_count[0x104] = 1

        free_cursor = rebuild_lzw_free_list_after_clear(parent, value, ref_count, free_codes)

        self.assertGreaterEqual(free_cursor, 0x101)
        self.assertEqual(parent[0x102], -1)
        self.assertEqual(parent[0x104], ord("A"))
        self.assertEqual(ref_count[0x104], 0)

    def test_real_paks_indexes_decode_when_local_assets_are_available(self):
        root = Path.home() / ".wine-hsl-original/drive_c/hsl"
        movie = root / "movie.pak"
        hsl = root / "hsl.pak"
        if not movie.exists() or not hsl.exists():
            self.skipTest("local private HSL PAK fixtures are unavailable")

        movie_index = self.decode_local_paks_index(movie)
        hsl_index = self.decode_local_paks_index(hsl)
        movie_records = parse_paks_directory_records(
            movie_index["decoded"],
            entry_count=movie_index["paks"]["candidate_entry_count"],
            data_end_offset=movie_index["paks"]["candidate_index_offset"],
        )
        hsl_records = parse_paks_directory_records(
            hsl_index["decoded"],
            entry_count=hsl_index["paks"]["candidate_entry_count"],
            data_end_offset=hsl_index["paks"]["candidate_index_offset"],
        )

        self.assertEqual(
            [record["name"] for record in movie_records],
            [
                "?:\\movie\\start.snd",
                "?:\\movie\\start.ani",
                "?:\\movie\\end.ani",
                "?:\\movie\\End.snd",
            ],
        )
        self.assertEqual(len(hsl_records), 5600)
        self.assertEqual(hsl_records[0]["offset"], 0x18)
        self.assertEqual(hsl_records[1]["offset"], 0x1180)
        self.assertEqual(hsl_records[2]["offset"], 0x1A5C)
        self.assertTrue(all(record["within_data_region"] for record in hsl_records))
        self.assertGreaterEqual(len(hsl_index["trace_events"]), 1)

    def decode_local_paks_index(self, path: Path) -> dict:
        with path.open("rb") as handle:
            first_bytes = handle.read(0x40)
        paks = parse_paks_header(first_bytes)
        self.assertIsNotNone(paks)
        paks = dict(paks or {})
        add_paks_derived_fields(paks, path.stat().st_size)
        with path.open("rb") as handle:
            handle.seek(paks["candidate_index_offset"])
            compressed = handle.read()
        trace_events: list[dict[str, int | str]] = []
        decoded = decode_lzw_index_block(
            compressed,
            output_limit=paks["candidate_index_allocation_size"],
            trace_events=trace_events,
        )
        return {"paks": paks, "decoded": decoded, "trace_events": trace_events}

    def test_parse_paks_directory_records_reads_exe_loader_layout(self):
        record = (
            (5).to_bytes(4, "little")
            + (0x1234).to_bytes(4, "little")
            + (7).to_bytes(4, "little")
            + b"DATA\\LEVEL000.BIN\x00".ljust(32, b"\x00")
        )

        records = parse_paks_directory_records(record, entry_count=1)

        self.assertEqual(
            records,
            [
                {
                    "index": 0,
                    "offset": 0x1234,
                    "length": 5,
                    "unknown_0x08": 7,
                    "name": "DATA\\LEVEL000.BIN",
                }
            ],
        )

    def test_parse_paks_header_rejects_non_paks_input(self):
        self.assertIsNone(parse_paks_header(b"not-a-paks-file"))

    def test_signature_scan_returns_offsets_without_payload(self):
        data = b"abcRIFF1234WAVEzzBMtail"

        hits = scan_embedded_signatures(data)

        self.assertEqual(
            hits,
            [
                {"signature": "riff", "offset": 3},
                {"signature": "bmp", "offset": 17},
            ],
        )

    def test_guess_type_classifies_pe_and_json_manifest_is_serializable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "game.exe").write_bytes(b"MZ" + b"\x00" * 30 + b"MAGIC\\SP00_001.SHP\x00")
            manifest = scan_directory(root)

        self.assertEqual(guess_type(b"MZ" + b"\x00" * 6), "pe_executable")
        self.assertEqual(manifest["files"][0]["resource_string_hints"], ["MAGIC\\SP00_001.SHP"])
        json.dumps(manifest)

    def test_resource_string_hints_are_filtered_and_limited(self):
        data = b"MAGIC\\SP00_001.SHP\x00not-resource\x00MOVIE\\OP01.AVI\x00"

        hints = find_resource_string_hints(data, max_hints=1)

        self.assertEqual(hints, ["MAGIC\\SP00_001.SHP"])

    def test_xor_a8_wave_candidates_report_offsets_without_payload(self):
        with tempfile.TemporaryDirectory() as tmp:
            wave = self.build_xor_a8_wave(b"\x00\x00")
            path = Path(tmp) / "movie.pak"
            path.write_bytes(b"\x00" * 12 + wave + b"tail")

            candidates = scan_xor_a8_wave_candidates(path)
            decoded = decoded_xor_a8_wave_bytes(path, candidates[0])

        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0]["offset"], 12)
        self.assertEqual(candidates[0]["candidate_end_offset"], 12 + len(wave))
        self.assertEqual(candidates[0]["channels"], 1)
        self.assertTrue(decoded.startswith(b"RIFF"))
        self.assertEqual(decoded[8:12], b"WAVE")
        self.assertIn(b"data", decoded[:64])
