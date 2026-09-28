import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from tools.hsl_payload_inspector import (
    build_first_battle_mechanics_fixture,
    build_report,
    inspect_payload,
    parse_args,
    parse_worl,
    build_chapter01_generated_metadata,
    build_chapter01_imported_audio_normalized,
    build_chapter01_imported_map_objects,
    build_chapter01_imported_message_text_evidence,
    build_chapter01_imported_resource_refs,
    build_chapter01_imported_shape_preview_index,
    build_chapter01_imported_ui_preview_index,
    build_chapter01_script_ir,
    write_chapter01_generated_metadata,
    write_chapter01_imported_map_object_ir,
    write_chapter01_imported_script_ir,
)
from hsltools.sources.scripts import EVEF_RECORD_SIZE, parse_action_chain, parse_evef, parse_text_metadata
from hsltools.sources.shp import parse_shp, shp_pixel_values


class PayloadInspectorTests(unittest.TestCase):
    def test_cli_requires_explicit_manifest(self):
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                parse_args([])
        self.assertEqual(raised.exception.code, 2)

        args = parse_args(["--manifest", "/tmp/resource-scan.json", "--no-previews"])
        self.assertEqual(args.manifest, Path("/tmp/resource-scan.json"))
        self.assertTrue(args.no_previews)

    def build_shp(self) -> bytes:
        width = 2
        height = 2
        first_row_offset = 0x24 + height * 4
        row_size = width * 2 + 6
        header = (
            b"TLHS"
            + (0).to_bytes(4, "little")
            + (2).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (0x1234).to_bytes(4, "little")
            + width.to_bytes(4, "little")
            + height.to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
        )
        offsets = first_row_offset.to_bytes(4, "little") + (
            first_row_offset + row_size
        ).to_bytes(4, "little")
        row0 = (0).to_bytes(2, "little") + width.to_bytes(2, "little")
        row0 += (0xF800).to_bytes(2, "little") + (0x07E0).to_bytes(2, "little")
        row0 += (0xFFFF).to_bytes(2, "little")
        row1 = (0).to_bytes(2, "little") + width.to_bytes(2, "little")
        row1 += (0x001F).to_bytes(2, "little") + (0xFFFF).to_bytes(2, "little")
        row1 += (0xFFFF).to_bytes(2, "little")
        return header + offsets + row0 + row1

    def build_xor_a8_header_wav(self) -> bytes:
        pcm = b"\x00\x00\x01\x00"
        riff_size = 36 + len(pcm)
        header = (
            b"RIFF"
            + riff_size.to_bytes(4, "little")
            + b"WAVE"
            + b"fmt "
            + (16).to_bytes(4, "little")
            + (1).to_bytes(2, "little")
            + (1).to_bytes(2, "little")
            + (22050).to_bytes(4, "little")
            + (44100).to_bytes(4, "little")
            + (2).to_bytes(2, "little")
            + (16).to_bytes(2, "little")
        )
        return bytes(byte ^ 0xA8 for byte in header) + b"data" + len(pcm).to_bytes(4, "little") + pcm

    def test_parse_shp_validates_row_table_and_rgb565_payload(self):
        data = self.build_shp()

        shp = parse_shp(data)

        self.assertEqual(shp["width"], 2)
        self.assertEqual(shp["height"], 2)
        self.assertEqual(shp["row_table_entries"], 2)
        self.assertTrue(shp["all_rows_decode"])
        self.assertTrue(shp["all_rows_full_width_single_segment"])
        self.assertTrue(shp["first_row_is_after_table"])
        self.assertEqual(shp_pixel_values(data, shp), [0xF800, 0x07E0, 0x001F, 0xFFFF])
        self.assertEqual(shp["pixel_value_summary"]["present_pixel_count"], 4)
        self.assertEqual(shp["pixel_value_summary"]["transparent_gap_count"], 0)
        self.assertEqual(shp["pixel_value_summary"]["top_rgb565_values"][0], {"rgb565_hex": "0xf800", "count": 1})
        self.assertEqual(shp["pixel_value_summary"]["header_0x10_rgb565_hex"], "0x1234")
        self.assertFalse(shp["pixel_value_summary"]["header_0x10_value_seen_in_pixels"])

    def test_parse_evef_confirms_fixed_record_count_layout(self):
        data = (
            b"EVEF"
            + (2).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (0x10 + 2 * EVEF_RECORD_SIZE).to_bytes(4, "little")
            + bytearray(EVEF_RECORD_SIZE * 2)
        )

        evef = parse_evef(bytes(data))

        self.assertEqual(evef["record_count"], 2)
        self.assertTrue(evef["size_matches_declared"])
        self.assertTrue(evef["size_matches_count_times_record_size"])

    def test_parse_worl_confirms_grid_size_without_exporting_cells(self):
        data = (
            b"WORL"
            + (3).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (2).to_bytes(4, "little")
            + (3).to_bytes(4, "little")
            + (4).to_bytes(4, "little")
            + b"\x00" * (2 * 3 * 4)
        )

        worl = parse_worl(data)

        self.assertEqual(worl["width_candidate_0x0c"], 2)
        self.assertEqual(worl["height_candidate_0x10"], 3)
        self.assertTrue(worl["size_matches_grid"])
        self.assertEqual(worl["cell_count"], 6)

    def test_parse_text_metadata_detects_cp950_resources_objects_and_actions(self):
        text = (
            "#include ACTION.H\r\n"
            "[Object]\r\n"
            "obj_code = 1\r\n"
            "obj_name = Demo\r\n"
            "obj_Shape_Name = SHAPE\\TITLE021.SHP\r\n"
            "obj_Shape_Number = 1\r\n"
            "action = actMessage(WORD001)\r\n"
            "; 敵人全滅\r\n"
        ).encode("cp950")

        meta = parse_text_metadata(text)

        self.assertEqual(meta["encoding"], "cp950")
        self.assertEqual(meta["includes"], ["ACTION.H"])
        self.assertEqual(meta["section_counts"], {"Object": 1})
        self.assertEqual(meta["object_count"], 1)
        self.assertEqual(meta["resource_refs"], ["SHAPE\\TITLE021.SHP"])
        self.assertEqual(meta["action_counts"], {"actMessage": 1})

    def test_build_report_consumes_manifest_paths_and_extra_roots(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload = root / "face.shp"
            payload.write_bytes(self.build_shp())
            extra = root / "extra"
            extra.mkdir()
            (extra / "event.bin").write_bytes(
                b"EVEF"
                + (1).to_bytes(4, "little")
                + (0).to_bytes(4, "little")
                + (0x10 + EVEF_RECORD_SIZE).to_bytes(4, "little")
                + b"\x00" * EVEF_RECORD_SIZE
            )
            manifest = root / "manifest.json"
            manifest.write_text(
                json.dumps({"records": [{"output_path": payload.as_posix()}]}),
                encoding="utf-8",
            )

            report = build_report(manifest, [extra], preview_dir=None)

        self.assertEqual(report["payload_count"], 2)
        self.assertEqual(report["classification_counts"], {"shp": 1, "evef": 1})
        self.assertEqual([item["classification"] for item in report["payloads"]], ["shp", "evef"])

    def test_inspect_payload_classifies_ascii_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "story.txt"
            path.write_text("#include ACTION.H\n[story]\naction = actDelay(1)\n", encoding="ascii")

            item = inspect_payload(path)

        self.assertEqual(item["classification"], "text")
        self.assertEqual(item["encoding"], "ascii")
        self.assertEqual(item["action_counts"], {"actDelay": 1})

    def test_parse_action_chain_splits_nested_comma_actions(self):
        chain = parse_action_chain("actShowWinFailStatus,actDelay,20")

        self.assertEqual(
            chain,
            [
                {"name": "actShowWinFailStatus", "args": []},
                {"name": "actDelay", "args": ["20"]},
            ],
        )

    def test_parse_text_metadata_keeps_actor_install_words_for_actor_processes_only(self):
        # obj_X1 / obj_HitPoint are constructor install words on defProcEnemy / defProcPlayer
        # objects (0x407ec0); on an effect object obj_X1 is a WAV name nothing reads.
        text = (
            "[Object]\n"
            "obj_code = 96\n"
            "obj_name = Enemy062(村民)\n"
            "obj_Shape_Name = SHAPE\\062-00001.SHP\n"
            "obj_Process_Code = defProcEnemy\n"
            "obj_X1 = pmPlayerEnemy\n"
            "obj_HitPoint = 50\n"
            "obj_Data7 = 62\n"
            "[Object]\n"
            "obj_code = 300\n"
            "obj_name = FireBomb\n"
            "obj_Shape_Name = SHAPE\\BOMB.SHP\n"
            "obj_Process_Code = defProcEffect\n"
            "obj_X1 = WAV\\BOMB0004.WAV\n"
            "obj_HitPoint = 12\n"
            "obj_Data9 = effProcFireAndBomb\n"
        ).encode("cp950")

        meta = parse_text_metadata(text)

        fields = {block["obj_code"]: block["obj_data_fields"] for block in meta["objects"]}
        self.assertEqual(fields["96"], {"obj_X1": "pmPlayerEnemy", "obj_HitPoint": "50", "obj_Data7": "62"})
        self.assertEqual(fields["300"], {"obj_Data9": "effProcFireAndBomb"})

    def test_parse_text_metadata_tracks_repeated_sections_and_clean_action_names(self):
        text = (
            "#include ACTION.H\n"
            "[win] ; comment after section\n"
            "code = 0\n"
            "message = 1\n"
            "action = actCheckRoundNumber,6\n"
            "action = actShowWinFailStatus,actDelay,20\n"
            "[event]\n"
            "code = 1\n"
            "action = actInsertEventStatus,0\n"
            "[event]\n"
            "code = 2\n"
            "action = actDeleteEventStatus,0\n"
        ).encode("ascii")

        meta = parse_text_metadata(text)

        self.assertEqual(meta["section_counts"], {"win": 1, "event": 2})
        self.assertEqual(
            meta["action_counts"],
            {
                "actCheckRoundNumber": 1,
                "actShowWinFailStatus": 1,
                "actDelay": 1,
                "actInsertEventStatus": 1,
                "actDeleteEventStatus": 1,
            },
        )
        self.assertEqual(meta["section_blocks"][0]["codes"], ["0"])
        self.assertEqual(meta["section_blocks"][0]["messages"], ["1"])
        self.assertEqual(meta["section_blocks"][0]["message_count"], 1)
        self.assertEqual(meta["section_blocks"][0]["actions"][1]["chain"][1]["name"], "actDelay")

    def generated_report_fixture(self) -> dict:
        return {
            "payloads": [
                {
                    "path": "ignored/private/level051.wrd",
                    "width_candidate_0x0c": 24,
                    "height_candidate_0x10": 24,
                    "bytes_per_cell_candidate_0x14": 4,
                    "size_matches_grid": True,
                    "cell_count": 576,
                    "flagged_cell_count": 0,
                    "unflagged_cell_count": 576,
                    "unique_cell_values": 576,
                    "low24_unique_cell_values": 576,
                    "flag_counts": [{"flag_hex": "0x00", "count": 576}],
                    "low24_min": 0,
                    "low24_max": 575,
                    "low24_is_permutation_0_to_cell_count_minus_1": True,
                    "sample_rows_low24": [[0, 1, 2]],
                },
                {
                    "path": "ignored/private/level051.bin",
                    "record_count": 2,
                    "non_zero_record_count": 2,
                    "record_code_counts": {"6": 1, "21": 1},
                    "record_summaries": [
                        {
                            "index": 0,
                            "field_0x04_code_candidate": 6,
                            "placement_x_candidate_0x08": 10,
                            "placement_y_candidate_0x0c": 12,
                            "non_zero_u32": [{"field_offset": 4, "value": 6}],
                        },
                        {
                            "index": 1,
                            "field_0x04_code_candidate": 21,
                            "placement_x_candidate_0x08": 14,
                            "placement_y_candidate_0x0c": 9,
                            "non_zero_u32": [{"field_offset": 4, "value": 21}],
                        },
                    ],
                },
                {
                    "path": "ignored/private/obj-051.obs",
                    "object_count": 2,
                    "resource_refs": ["SHAPE\\DEMO.SHP"],
                    "objects": [
                        {
                            "obj_code": "6",
                            "obj_name": "Leonard",
                            "obj_process_code": "defProcPlayerInstall",
                            "obj_shape_name": "SHAPE\\LEONARD.SHP",
                            "obj_shape_number": "1",
                        },
                        {
                            "obj_code": "21",
                            "obj_name": "Enemy",
                            "obj_process_code": "defProcEnemy",
                            "obj_shape_name": "SHAPE\\ENEMY.SHP",
                            "obj_shape_number": "1",
                        },
                    ],
                },
                {
                    "path": "ignored/private/STORY051.TXT",
                    "section_counts": {"story": 1},
                    "action_counts": {
                        "actInsertFailStatus": 1,
                        "actInsertEventStatus": 4,
                        "actMessage": 3,
                        "actShowWinFailStatus": 1,
                    },
                    "section_blocks": [
                        {
                            "index": 0,
                            "name": "story",
                            "codes": [],
                            "messages": [],
                            "actions": [{"chain": [{"name": "actMessage", "args": ["WORD001"]}]}],
                        }
                    ],
                    "sha256": "not-for-tracked-export",
                    "first_bytes_hex": "616263",
                },
                {
                    "path": "ignored/private/winfail051.txt",
                    "section_counts": {"win": 2, "fail": 1, "event": 4},
                    "action_counts": {
                        "actCheckEnemyTotalNumber": 1,
                        "actCheckEnemyNumber": 2,
                        "actCheckPlayerArrivePos": 1,
                        "actCheckRoundNumber": 2,
                        "actDeleteEventStatus": 2,
                        "actInsertEventStatus": 2,
                        "actInsertWinStatus": 2,
                        "actShowWinFailStatus": 1,
                    },
                    "section_blocks": [
                        {
                            "index": 0,
                            "name": "event",
                            "codes": ["0"],
                            "messages": [],
                            "actions": [{"chain": [{"name": "actCheckRoundNumber", "args": ["6"]}]}],
                        }
                    ],
                },
                {
                    "path": "ignored/private/obj-051.h",
                    "define_values": {"Demo": "1"},
                },
            ]
        }

    def assert_forbidden_key_absent(self, value, forbidden: set[str]):
        if isinstance(value, dict):
            for key, child in value.items():
                self.assertNotIn(key, forbidden)
                self.assert_forbidden_key_absent(child, forbidden)
        elif isinstance(value, list):
            for child in value:
                self.assert_forbidden_key_absent(child, forbidden)

    def test_generated_chapter01_metadata_omits_raw_payload_fields(self):
        generated = build_chapter01_generated_metadata(self.generated_report_fixture())

        self.assert_forbidden_key_absent(
            generated,
            {
                "first_bytes_hex",
                "sha256",
                "pixels",
                "sample_rows_low24",
                "non_zero_u32",
                "sections",
                "chain",
                "preview_output_path",
                "normalized_output_path",
                "source_path",
                "flag_counts",
                "low24_min",
                "low24_max",
                "common_cell_values",
                "flagged_cell_samples",
            },
        )

    def test_generated_chapter01_metadata_keeps_compact_counts_and_candidates(self):
        generated = build_chapter01_generated_metadata(self.generated_report_fixture())

        self.assertEqual(generated["map_grid"]["dimensions"], {"width": 24, "height": 24})
        self.assertEqual(
            generated["map_grid"]["opaque_integrity"],
            {
                "cell_count": 576,
                "flagged_cell_count": 0,
                "unflagged_cell_count": 576,
                "low24_range": {"min": 0, "max": 575},
                "unique_cell_value_count": 576,
                "low24_unique_cell_value_count": 576,
                "low24_is_dense_cell_range": True,
                "summary_semantics": "opaque structural WORL integrity summary derived from parser counts only; raw cell rows, raw cell values, terrain, blockers, and movement costs are not exported or decoded",
            },
        )
        self.assertEqual(generated["evef"]["record_count"], 2)
        self.assertEqual(generated["placement_role_counts"], {"player_install": 1, "enemy": 1})
        self.assertEqual(generated["placement_aggregates"]["object_code_counts"], {"21": 1, "6": 1})
        self.assertEqual(generated["placement_aggregates"]["by_role"]["enemy"]["object_code_counts"], {"21": 1})
        self.assertEqual(generated["placement_aggregates"]["by_role"]["player_install"]["shape_id_counts"], {"LEONARD.SHP": 1})
        self.assertIn("coordinates, stats, terrain, and formulas remain unresolved", generated["placement_aggregates"]["summary_semantics"])
        self.assertEqual(
            generated["placement_join_integrity"],
            {
                "summary_semantics": "count-only EVEF/object join coverage summary; object names, raw object fields, coordinates, stats, terrain, AI, and formulas remain unresolved",
                "evef_record_count": 2,
                "non_zero_record_count": 2,
                "joined_record_count": 2,
                "unmatched_record_count": 0,
                "placed_object_code_count": 2,
                "object_record_count": 2,
                "role_coverage_counts": {"enemy": 1, "player_install": 1},
            },
        )
        self.assertEqual(generated["initial_placements"][0]["object_code"], 6)
        self.assertEqual(generated["initial_placements"][0]["role"], "player_install")
        self.assertEqual(generated["initial_placements"][0]["shape_id"], "LEONARD.SHP")
        self.assertEqual(generated["script_summary"]["winfail051"]["section_counts"]["event"], 4)
        self.assertEqual(
            generated["status_action_contract"],
            {
                "fail_status_count": 1,
                "event_status_insert_count": 6,
                "event_status_delete_count": 2,
                "win_status_count": 2,
                "round_check_count": 2,
                "enemy_total_check_count": 1,
                "enemy_number_check_count": 2,
                "arrival_check_count": 1,
                "source_semantics": "action-count contract derived only from STORY051.TXT action_counts and winfail051.txt action_counts/section_counts; not original status ids, action args, chains, or script order",
            },
        )
        self.assertEqual(
            generated["status_lifecycle_summary"],
            {
                "summary_semantics": "count-only lifecycle summary derived from status_action_contract; not original status ids, action args, chains, or script order",
                "fail": {"insert_count": 1},
                "event": {
                    "insert_count": 6,
                    "delete_count": 2,
                    "net_enabled_candidate": 4,
                },
                "win": {"insert_count": 2},
                "checks": {
                    "round": 2,
                    "enemy_total": 1,
                    "enemy_number": 2,
                    "arrival": 1,
                },
                "show_status_count": 2,
            },
        )

    def test_generated_chapter01_writer_creates_mechanics_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "content" / "generated" / "hsl" / "chapter01"

            write_chapter01_generated_metadata(self.generated_report_fixture(), output_dir)

            output = output_dir / "mechanics.json"
            self.assertTrue(output.exists())
            self.assertTrue((output_dir / "index.json").exists())
            self.assertTrue((output_dir / "map_grid.json").exists())
            self.assertTrue((output_dir / "initial_placements.json").exists())
            self.assertTrue((output_dir / "script_summary.json").exists())
            generated = json.loads(output.read_text(encoding="utf-8"))
            index = json.loads((output_dir / "index.json").read_text(encoding="utf-8"))
            placements = json.loads((output_dir / "initial_placements.json").read_text(encoding="utf-8"))
            self.assertEqual(generated["object_records"]["source_id"], "obj-051.obs")
            self.assertEqual(index["files"]["mechanics"], "mechanics.json")
            self.assertEqual(placements["placement_aggregates"], generated["placement_aggregates"])
            self.assertEqual(placements["placement_join_integrity"], generated["placement_join_integrity"])
            script_summary = json.loads((output_dir / "script_summary.json").read_text(encoding="utf-8"))
            self.assertEqual(
                script_summary["status_action_contract"],
                generated["status_action_contract"],
            )
            self.assertEqual(
                script_summary["status_lifecycle_summary"],
                generated["status_lifecycle_summary"],
            )

    def test_imported_chapter01_script_ir_preserves_order_args_and_refs(self):
        story = build_chapter01_script_ir(self.generated_report_fixture())

        self.assertEqual(story["evidence_tier"], "resource-derived")
        entries = {script["id"]: script for script in story["scripts"]}
        self.assertEqual(set(entries), {"story051", "winfail051"})
        self.assertEqual(entries["story051"]["file"], "scripts/story051.json")
        self.assertEqual(entries["story051"]["path"], "res://content/imported/hsl/chapter01/scripts/story051.json")
        self.assertEqual(entries["story051"]["evidence_tier"], "resource-derived")
        self.assertEqual(story["total_action_chain_count"], 2)
        self.assertEqual(entries["winfail051"]["action_chain_count"], 1)

    def test_imported_chapter01_writer_creates_script_ir_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "content" / "imported" / "hsl" / "chapter01"

            write_chapter01_imported_script_ir(self.generated_report_fixture(), output_dir)

            index_output = output_dir / "script_ir_index.json"
            story_output = output_dir / "scripts" / "story051.json"
            winfail_output = output_dir / "scripts" / "winfail051.json"
            self.assertTrue(index_output.exists())
            self.assertTrue(story_output.exists())
            self.assertTrue(winfail_output.exists())
            index = json.loads(index_output.read_text(encoding="utf-8"))
            story = json.loads(story_output.read_text(encoding="utf-8"))
            winfail = json.loads(winfail_output.read_text(encoding="utf-8"))
            self.assertEqual(story["evidence_tier"], "resource-derived")
            self.assertEqual(story["id"], "story051")
            self.assertEqual(story["source_file"], "STORY051.TXT")
            self.assertEqual(story["action_line_count"], 1)
            self.assertEqual(story["action_chain_count"], 1)
            self.assertEqual(story["action_chain"][0]["name"], "actMessage")
            self.assertEqual(story["action_chain"][0]["args"], ["WORD001"])
            self.assertEqual(story["sections"][0]["type"], "story")
            self.assertEqual(story["sections"][0]["actions"][0]["name"], "actMessage")
            self.assertEqual(story["sections"][0]["actions"][0]["chain"][0]["args"], ["WORD001"])
            self.assertEqual(winfail["sections"][0]["actions"][0]["primary"], "actCheckRoundNumber")
            self.assertEqual(winfail["sections"][0]["actions"][0]["chain"][0]["args"], ["6"])

    def test_parse_evef_exposes_record_code_and_coordinate_candidates(self):
        record0 = bytearray(EVEF_RECORD_SIZE)
        record0[4:8] = (6).to_bytes(4, "little")
        record0[8:12] = (480).to_bytes(4, "little")
        record0[12:16] = (640).to_bytes(4, "little")
        data = (
            b"EVEF"
            + (1).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (0x10 + EVEF_RECORD_SIZE).to_bytes(4, "little")
            + bytes(record0)
        )

        evef = parse_evef(data)

        self.assertEqual(evef["record_code_counts"], {"6": 1})
        self.assertEqual(
            evef["record_summaries"],
            [
                {
                    "index": 0,
                    "offset": 16,
                    "field_0x04_code_candidate": 6,
                    "placement_x_candidate_0x08": 480,
                    "placement_y_candidate_0x0c": 640,
                    "non_zero_u32": [
                        {"field_offset": 4, "value": 6},
                        {"field_offset": 8, "value": 480},
                        {"field_offset": 12, "value": 640},
                    ],
                }
            ],
        )

    def test_parse_worl_summarizes_flags_without_exporting_grid(self):
        cells = [
            0,
            1,
            0xFF000002,
            0x00000320,
        ]
        data = (
            b"WORL"
            + (3).to_bytes(4, "little")
            + (0).to_bytes(4, "little")
            + (2).to_bytes(4, "little")
            + (2).to_bytes(4, "little")
            + (4).to_bytes(4, "little")
            + b"".join(value.to_bytes(4, "little") for value in cells)
        )

        worl = parse_worl(data)

        self.assertEqual(worl["cell_count"], 4)
        self.assertEqual(worl["flagged_cell_count"], 1)
        self.assertEqual(worl["unflagged_cell_count"], 3)
        self.assertEqual(worl["unique_cell_values"], 4)
        self.assertEqual(worl["low24_unique_cell_values"], 4)
        self.assertEqual(worl["flag_counts"], [{"flag_hex": "0x00", "count": 3}, {"flag_hex": "0xff", "count": 1}])
        self.assertEqual(worl["low24_min"], 0)
        self.assertEqual(worl["low24_max"], 800)
        self.assertFalse(worl["low24_is_permutation_0_to_cell_count_minus_1"])
        self.assertEqual(worl["flagged_cell_samples"][0]["x"], 0)
        self.assertEqual(worl["flagged_cell_samples"][0]["y"], 1)
        self.assertEqual(worl["cell_table"][2]["raw_value_hex"], "0xff000002")
        self.assertEqual(worl["cell_table"][2]["low24_tile_ref_candidate"], 2)
        self.assertEqual(worl["cell_table"][2]["high8_flag_candidate_hex"], "0xff")
        self.assertEqual(worl["cell_table"][2]["interpretation_status"], "unresolved")

    def test_build_first_battle_fixture_joins_evef_records_to_obs_objects(self):
        report = {
            "payloads": [
                {
                    "path": "level051.bin",
                    "classification": "evef",
                    "record_count": 2,
                    "non_zero_record_count": 2,
                    "record_code_counts": {"6": 1, "96": 1},
                    "record_summaries": [
                        {
                            "index": 0,
                            "field_0x04_code_candidate": 6,
                            "placement_x_candidate_0x08": 480,
                            "placement_y_candidate_0x0c": 640,
                            "non_zero_u32": [],
                        },
                        {
                            "index": 1,
                            "field_0x04_code_candidate": 96,
                            "placement_x_candidate_0x08": 544,
                            "placement_y_candidate_0x0c": 576,
                            "non_zero_u32": [],
                        },
                    ],
                },
                {
                    "path": "level051.wrd",
                    "classification": "worl",
                    "width_candidate_0x0c": 24,
                    "height_candidate_0x10": 24,
                    "bytes_per_cell_candidate_0x14": 4,
                    "size_matches_grid": True,
                    "cell_count": 576,
                    "flagged_cell_count": 123,
                    "unflagged_cell_count": 453,
                    "unique_cell_values": 576,
                    "low24_unique_cell_values": 576,
                    "flag_counts": [{"flag_hex": "0x00", "count": 453}],
                    "low24_min": 0,
                    "low24_max": 943,
                    "low24_is_permutation_0_to_cell_count_minus_1": False,
                },
                {
                    "path": "obj-051.obs",
                    "classification": "text",
                    "object_count": 2,
                    "objects": [
                        {
                            "obj_code": "6",
                            "obj_name": "Leonard",
                            "obj_process_code": "defProcPlayerInstall",
                            "obj_shape_name": "SHAPE\\001-00001.SHP",
                        },
                        {
                            "obj_code": "96",
                            "obj_name": "Enemy023",
                            "obj_process_code": "defProcEnemy",
                            "obj_shape_name": "SHAPE\\023-00001.SHP",
                        },
                    ],
                    "resource_refs": ["SHAPE\\001-00001.SHP", "SHAPE\\023-00001.SHP"],
                },
            ]
        }

        fixture = build_first_battle_mechanics_fixture(report)

        self.assertEqual(fixture["map_grid"]["dimensions"], {"width": 24, "height": 24})
        self.assertEqual(fixture["map_grid"]["opaque_integrity"]["cell_count"], 576)
        self.assertEqual(fixture["initial_placements"][0]["object_name"], "Leonard")
        self.assertEqual(fixture["initial_placements"][1]["role"], "enemy")
        self.assertEqual(fixture["placement_role_counts"], {"player_install": 1, "enemy": 1})

    def imported_map_object_report_fixture(self) -> dict:
        return {
            "payloads": [
                {
                    "path": "level051.bin",
                    "classification": "evef",
                    "record_count": 2,
                    "non_zero_record_count": 2,
                    "record_summaries": [
                        {
                            "index": 0,
                            "offset": 0x10,
                            "field_0x04_code_candidate": 6,
                            "placement_x_candidate_0x08": 480,
                            "placement_y_candidate_0x0c": 640,
                            "non_zero_u32": [
                                {"field_offset": 4, "value": 6},
                                {"field_offset": 8, "value": 480},
                                {"field_offset": 12, "value": 640},
                                {"field_offset": 32, "value": 7},
                            ],
                        },
                        {
                            "index": 1,
                            "offset": 0xE0,
                            "field_0x04_code_candidate": 96,
                            "placement_x_candidate_0x08": 544,
                            "placement_y_candidate_0x0c": 576,
                            "non_zero_u32": [],
                        },
                    ],
                },
                {
                    "path": "level051.wrd",
                    "classification": "worl",
                    "width_candidate_0x0c": 2,
                    "height_candidate_0x10": 2,
                    "bytes_per_cell_candidate_0x14": 4,
                    "size_matches_grid": True,
                    "cell_count": 4,
                    "flagged_cell_count": 1,
                    "unflagged_cell_count": 3,
                    "unique_cell_values": 4,
                    "low24_unique_cell_values": 4,
                    "low24_min": 0,
                    "low24_max": 3,
                    "flag_counts": [{"flag_hex": "0x00", "count": 3}, {"flag_hex": "0xff", "count": 1}],
                    "cell_table": [
                        {
                            "index": 0,
                            "x": 0,
                            "y": 0,
                            "raw_value_hex": "0x00000000",
                            "low24_tile_ref_candidate": 0,
                            "high8_flag_candidate_hex": "0x00",
                            "source_kind": "resource-derived",
                            "evidence_tier": "resource_parser_candidate",
                            "interpretation_status": "unresolved",
                        }
                    ],
                },
                {
                    "path": "obj-051.obs",
                    "classification": "text",
                    "object_count": 2,
                    "objects": [
                        {
                            "obj_code": "6",
                            "obj_name": "Leonard",
                            "obj_process_code": "defProcPlayerInstall",
                            "obj_shape_name": "SHAPE\\001-00001.SHP",
                            "obj_shape_number": "1",
                            "obj_data_fields": {"obj_Data0": "SID_PLAYER0", "obj_Collide_X": "32"},
                            "fields_present": ["obj_code", "obj_name", "obj_Data0", "obj_Collide_X"],
                        },
                        {
                            "obj_code": "96",
                            "obj_name": "Enemy023",
                            "obj_process_code": "defProcEnemy",
                            "obj_shape_name": "SHAPE\\023-00001.SHP",
                            "obj_shape_number": "1",
                            "obj_data_fields": {"obj_Data0": "SID_ENEMY023"},
                            "fields_present": ["obj_code", "obj_name", "obj_Data0"],
                        },
                        {
                            "obj_code": "17",
                            "obj_name": "Tree",
                            "obj_process_code": "defProcStandObject",
                            "obj_shape_name": "SHAPE01\\tree07.SHP",
                            "obj_shape_number": "2",
                            "obj_data_fields": {"obj_ReadShape": "TRUE"},
                            "fields_present": ["obj_code", "obj_name", "obj_ReadShape"],
                        },
                        {
                            "obj_code": "2",
                            "obj_name": "Cursor",
                            "obj_process_code": "defProcCursor",
                            "obj_shape_name": "SHAPE\\CURSOR01.SHP",
                            "obj_shape_number": "3",
                            "obj_data_fields": {},
                            "fields_present": ["obj_code", "obj_name"],
                        },
                        {
                            "obj_code": "30",
                            "obj_name": "MagicEffect",
                            "obj_process_code": "defProcStandObject",
                            "obj_shape_name": "MAGIC\\AIR06_03.SHP",
                            "obj_shape_number": "4",
                            "obj_data_fields": {},
                            "fields_present": ["obj_code", "obj_name"],
                        },
                        {
                            "obj_code": "31",
                            "obj_name": "UnknownShape",
                            "obj_process_code": "defProcUnknown",
                            "obj_shape_name": "SHAPE\\UNKNOWN.SHP",
                            "obj_shape_number": "5",
                            "obj_data_fields": {},
                            "fields_present": ["obj_code", "obj_name"],
                        },
                        {
                            "obj_code": "32",
                            "obj_name": "SymbolicEnemy",
                            "obj_process_code": "defProcEnemy",
                            "obj_shape_name": "SHAPE\\024-00001.SHP",
                            "obj_shape_number": "ENEMY024_Total",
                            "obj_data_fields": {},
                            "fields_present": ["obj_code", "obj_name"],
                        },
                    ],
                },
            ]
        }

    def test_imported_map_objects_preserves_field_level_reverse_engineering_ir(self):
        imported = build_chapter01_imported_map_objects(self.imported_map_object_report_fixture())

        self.assertEqual(imported["join_integrity"]["joined_record_count"], 2)
        self.assertEqual(imported["placements"][0]["record_offset_hex"], "0x10")
        self.assertEqual(imported["placements"][0]["object_name"], "Leonard")
        self.assertEqual(imported["placements"][0]["shape_resource_id"], "001-00001.SHP")
        self.assertEqual(imported["placements"][0]["evef_fields"]["field_0x04_code_candidate"]["field_offset_hex"], "0x04")
        self.assertEqual(imported["placements"][0]["evef_fields"]["u32_0x20"]["interpretation_status"], "unresolved")
        self.assertEqual(imported["placements"][0]["object_fields"]["obj_Data0"]["value"], "SID_PLAYER0")
        self.assertEqual(imported["placements"][0]["object_fields"]["obj_Data0"]["source_kind"], "resource-derived")
        self.assertIn("unresolved", imported["unresolved_semantics"][1])

    def test_imported_writer_creates_only_current_manifests(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp) / "content" / "imported" / "hsl" / "chapter01"
            for obsolete in [
                "asset_browser_index.json",
                "audio_resources.json",
                "blocking_placement.json",
                "map_grid.json",
                "shape_atlas_plan.json",
                "shape_previews.json",
                "terrain_cost_evidence.json",
                "terrain_placement_projection.json",
            ]:
                output_dir.mkdir(parents=True, exist_ok=True)
                (output_dir / obsolete).write_text("stale", encoding="utf-8")

            write_chapter01_imported_map_object_ir(
                self.imported_map_object_report_fixture(), output_dir
            )

            map_objects = json.loads((output_dir / "map_objects.json").read_text(encoding="utf-8"))
            resource_refs = json.loads((output_dir / "resource_refs.json").read_text(encoding="utf-8"))
            ui_resources = json.loads((output_dir / "ui_resources.json").read_text(encoding="utf-8"))
            ui_preview_index = json.loads((output_dir / "ui_preview_index.json").read_text(encoding="utf-8"))
            audio_normalized = json.loads((output_dir / "audio_normalized.json").read_text(encoding="utf-8"))
            message_evidence = json.loads((output_dir / "message_text_evidence.json").read_text(encoding="utf-8"))
            shape_preview_index = json.loads((output_dir / "shape_preview_index.json").read_text(encoding="utf-8"))

            self.assertEqual(map_objects["placements"][1]["role"], "enemy")
            self.assertEqual(ui_resources["resources"], resource_refs["battle_ui_resources"])
            for obsolete in [
                "asset_browser_index.json",
                "audio_resources.json",
                "blocking_placement.json",
                "map_grid.json",
                "shape_atlas_plan.json",
                "shape_previews.json",
                "terrain_cost_evidence.json",
                "terrain_placement_projection.json",
            ]:
                self.assertFalse((output_dir / obsolete).exists(), obsolete)

    def test_imported_writer_generates_shape_preview_pngs_for_resolved_payloads(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload = root / "legal-assets" / "derived" / "w16-ui-resource-import" / "hsl" / "drive_at" / "shape" / "001-00001.shp"
            payload.parent.mkdir(parents=True)
            payload.write_bytes(self.build_shp())
            report = self.imported_map_object_report_fixture()
            report["payloads"].append(
                {
                    "path": payload.as_posix(),
                    "classification": "shp",
                    **parse_shp(payload.read_bytes()),
                }
            )
            output_dir = root / "content" / "imported" / "hsl" / "chapter01"

            write_chapter01_imported_map_object_ir(report, output_dir)

            preview_index = json.loads((output_dir / "shape_preview_index.json").read_text(encoding="utf-8"))
            self.assertEqual(preview_index["summary"]["entry_count"], 1)
            self.assertEqual(preview_index["entries"][0]["resource_id"], "001-00001.SHP")
            preview_path = output_dir.parent / "shared" / preview_index["entries"][0]["preview_relpath"]
            self.assertTrue(preview_path.exists())
            self.assertEqual(preview_path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(preview_index["summary"], {"entry_count": 1, "category_counts": {"actor_sprite": 1}})
            self.assertEqual(preview_index["entries"][0]["display_order"], 0)
            self.assertEqual(preview_index["entries"][0]["preview_res_path"], "res://content/imported/hsl/shared/shape_previews/actor_sprite/001-00001.SHP.png")
            self.assertEqual(preview_index["entries"][0]["category"], "actor_sprite")

    def test_imported_writer_generates_normalized_audio_wav_artifacts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            payload = root / "legal-assets" / "derived" / "w12-first-chapter" / "hsl" / "drive_at" / "wav" / "Accept01.WAV"
            payload.parent.mkdir(parents=True)
            payload.write_bytes(self.build_xor_a8_header_wav())
            report = self.imported_map_object_report_fixture()
            report["payloads"].append(
                {
                    "path": payload.as_posix(),
                    "classification": "wav",
                    "decoded_wave": {
                        "channels": 1,
                        "sample_rate": 22050,
                        "bits_per_sample": 16,
                        "frame_count": 2,
                    },
                    "route_decision": "normalize XOR-A8 RIFF/WAVE header before Godot/Python WAV consumption",
                }
            )
            output_dir = root / "content" / "imported" / "hsl" / "chapter01"

            write_chapter01_imported_map_object_ir(report, output_dir)

            audio = json.loads((output_dir / "audio_normalized.json").read_text(encoding="utf-8"))
            self.assertEqual(audio["summary"], {"normalized_count": 1, "skipped_count": 0})
            item = audio["normalized_audio"][0]
            self.assertEqual(item["source_id"], "Accept01.WAV")
            self.assertEqual(item["normalized_res_path"], "res://content/imported/hsl/chapter01/audio_normalized/Accept01.WAV")
            self.assertEqual(item["trigger_semantics_status"], "unresolved")
            wav_path = output_dir / item["normalized_relpath"]
            data = wav_path.read_bytes()
            self.assertEqual(data[:4], b"RIFF")
            self.assertEqual(data[8:12], b"WAVE")

    def test_audio_normalized_manifest_keeps_trigger_semantics_unresolved(self):
        audio = build_chapter01_imported_audio_normalized({"available_audio": []}, Path("/tmp/not-used"))

        self.assertEqual(audio["summary"], {"normalized_count": 0, "skipped_count": 0})
        self.assertIn("trigger semantics remain unresolved", audio["unresolved_semantics"][0])

    def test_ui_preview_index_joins_ui_resources_to_preview_res_paths_without_command_identity(self):
        ui_resources = {
            "resources": [
                {
                    "resource_id": "BCMD01_1.SHP",
                    "ui_group": "battle_command_icon",
                    "dimensions": {"width": 42, "height": 42},
                    "process_hints": ["defProcBattleCommandString"],
                    "object_codes": ["110"],
                    "shape_number_candidates": ["3"],
                    "owner_semantics": {"semantic_status": "unresolved"},
                    "evidence_tier": "resource_imported",
                }
            ],
            "summary": {"ui_group_counts": {"battle_command_icon": 1}},
        }
        preview_index = {
            "entries": [
                {
                    "resource_id": "BCMD01_1.SHP",
                    "category": "battle_ui",
                    "dimensions": {"width": 42, "height": 42},
                    "preview_relpath": "shape_previews/battle_ui/BCMD01_1.SHP.png",
                    "preview_res_path": "res://content/imported/hsl/shared/shape_previews/battle_ui/BCMD01_1.SHP.png",
                    "frame_semantics_status": "unresolved",
                    "evidence_tier": "resource_imported",
                }
            ]
        }

        index = build_chapter01_imported_ui_preview_index(ui_resources, preview_index)

        self.assertEqual(index["summary"], {"entry_count": 1, "ui_group_counts": {"battle_command_icon": 1}, "missing_preview_count": 0})
        entry = index["entries"][0]
        self.assertEqual(entry["resource_id"], "BCMD01_1.SHP")
        self.assertEqual(entry["ui_group"], "battle_command_icon")
        self.assertEqual(entry["preview_res_path"], "res://content/imported/hsl/shared/shape_previews/battle_ui/BCMD01_1.SHP.png")
        self.assertEqual(entry["owner_semantics_status"], "unresolved")
        self.assertEqual(entry["command_identity_status"], "unresolved")
        self.assertEqual(entry["frame_semantics_status"], "unresolved")

    def test_shape_preview_index_exposes_godot_res_paths_without_frame_semantics(self):
        previews = {
            "previews": [
                {
                    "resource_id": "001-00001.SHP",
                    "atlas_group": "actor_sprite",
                    "preview_relpath": "shape_previews/actor_sprite/001-00001.SHP.png",
                    "dimensions": {"width": 36, "height": 76},
                    "frame_semantics_status": "unresolved",
                    "evidence_tier": "resource_imported",
                }
            ]
        }

        index = build_chapter01_imported_shape_preview_index(previews)

        self.assertEqual(index["sources"], {"resource_refs": "resource_refs.json"})
        self.assertEqual(index["entries"][0]["preview_res_path"], "res://content/imported/hsl/shared/shape_previews/actor_sprite/001-00001.SHP.png")
        self.assertEqual(index["entries"][0]["dimensions"], {"width": 36, "height": 76})
        self.assertEqual(index["entries"][0]["frame_semantics_status"], "unresolved")

    def test_message_text_evidence_records_negative_search_and_word_shape_hint(self):
        report = self.generated_report_fixture()
        report["payloads"].append(
            {
                "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape01/level51.shp",
                "classification": "shp",
                "width": 120,
                "height": 24,
            }
        )
        report["payloads"][3]["resource_refs"] = ["SHAPE01\\WORD051.SHP"]
        report["payloads"][3]["section_blocks"][0]["actions"] = [
            {"chain": [{"name": "actMessage", "args": ["SID_PLAYER0", "363"]}]}
        ]
        evidence = build_chapter01_imported_message_text_evidence(report)

        self.assertEqual(evidence["message_text_status"], "not_resolved_in_imported_assets")
        self.assertEqual(
            evidence["sources"],
            {"script_ir": "script_ir_index.json", "resource_refs": "resource_refs.json"},
        )
        self.assertEqual(evidence["summary"]["structured_text_table_candidate_count"], 0)
        self.assertIn("363", evidence["script_message_id_candidates"])
        self.assertEqual(evidence["word_shape_resource_refs"], ["SHAPE01\\WORD051.SHP"])
        self.assertIn("legal-assets/derived/w16-ui-resource-import", evidence["searched_payload_roots"])
        self.assertIn(".shp", evidence["searched_file_type_counts"])
        self.assertIn("no structured message text table payload", evidence["negative_evidence"][0])

    def test_imported_resource_refs_join_object_shapes_to_payload_metadata(self):
        report = self.imported_map_object_report_fixture()
        report["payloads"].extend(
            [
                {
                    "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape/001-00001.shp",
                    "classification": "shp",
                    "width": 32,
                    "height": 48,
                    "row_table_entries": 48,
                    "row_encoding_hypothesis": "test row encoding",
                    "row_header_summary": {
                        "coverage_min": 12,
                        "coverage_max": 32,
                        "segment_count_common": [{"count": 1, "rows": 40}, {"count": 2, "rows": 8}],
                        "common_coverage": [{"pixels": 32, "rows": 20}],
                    },
                    "all_rows_decode": True,
                    "all_rows_full_width_single_segment": False,
                    "bytes_per_pixel_candidate": 2,
                    "color_key_or_flags_0x10": 0,
                    "pixel_value_summary": {
                        "present_pixel_count": 100,
                        "transparent_gap_count": 1436,
                        "top_rgb565_values": [],
                        "header_0x10_rgb565_hex": "0x0000",
                        "header_0x10_value_seen_in_pixels": False,
                    },
                },
                {
                    "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape/024-00001.SHP",
                    "classification": "shp",
                    "width": 45,
                    "height": 64,
                    "row_table_entries": 64,
                    "row_encoding_hypothesis": "test row encoding",
                    "row_header_summary": {
                        "coverage_min": 3,
                        "coverage_max": 29,
                        "segment_count_common": [{"count": 2, "rows": 40}],
                        "common_coverage": [{"pixels": 18, "rows": 12}],
                    },
                    "all_rows_decode": True,
                    "all_rows_full_width_single_segment": False,
                    "bytes_per_pixel_candidate": 2,
                    "color_key_or_flags_0x10": 0,
                },
                {
                    "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape01/tree07.SHP",
                    "classification": "shp",
                    "width": 48,
                    "height": 64,
                    "row_table_entries": 64,
                    "row_encoding_hypothesis": "test row encoding",
                    "row_header_summary": {
                        "coverage_min": 4,
                        "coverage_max": 48,
                        "segment_count_common": [{"count": 2, "rows": 64}],
                        "common_coverage": [{"pixels": 24, "rows": 20}],
                    },
                    "all_rows_decode": True,
                    "all_rows_full_width_single_segment": False,
                    "bytes_per_pixel_candidate": 2,
                    "color_key_or_flags_0x10": 0,
                },
                {
                    "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape/cursor01.shp",
                    "classification": "shp",
                    "width": 16,
                    "height": 16,
                    "row_table_entries": 16,
                    "row_encoding_hypothesis": "test row encoding",
                    "row_header_summary": {
                        "coverage_min": 16,
                        "coverage_max": 16,
                        "segment_count_common": [{"count": 1, "rows": 16}],
                        "common_coverage": [{"pixels": 16, "rows": 16}],
                    },
                    "all_rows_decode": True,
                    "all_rows_full_width_single_segment": True,
                    "bytes_per_pixel_candidate": 2,
                    "color_key_or_flags_0x10": 0,
                },
                {
                    "path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/magic/air06_03.SHP",
                    "classification": "shp",
                    "width": 19,
                    "height": 20,
                    "row_table_entries": 20,
                    "row_encoding_hypothesis": "test row encoding",
                    "row_header_summary": {
                        "coverage_min": 3,
                        "coverage_max": 19,
                        "segment_count_common": [{"count": 3, "rows": 20}],
                        "common_coverage": [{"pixels": 12, "rows": 8}],
                    },
                    "all_rows_decode": True,
                    "all_rows_full_width_single_segment": False,
                    "bytes_per_pixel_candidate": 2,
                    "color_key_or_flags_0x10": 0,
                },
                {
                    "path": "legal-assets/derived/w12-first-chapter/hsl/drive_at/wav/Accept01.WAV",
                    "classification": "wav",
                    "decoded_wave": {
                        "channels": 1,
                        "sample_rate": 22050,
                        "bits_per_sample": 16,
                        "frame_count": 2205,
                    },
                    "route_decision": "normalize XOR-A8 RIFF/WAVE header before Godot/Python WAV consumption",
                },
            ]
        )

        refs = build_chapter01_imported_resource_refs(report)

        self.assertEqual(refs["summary"]["object_shape_ref_count"], 7)
        self.assertEqual(refs["summary"]["resolved_shape_payload_count"], 5)
        self.assertEqual(refs["summary"]["unresolved_shape_ref_count"], 2)
        self.assertEqual(refs["summary"]["available_audio_count"], 1)
        self.assertEqual(
            refs["summary"]["resource_category_counts"],
            {
                "actor_sprite": 3,
                "battle_ui": 1,
                "magic_effect": 1,
                "map_object": 1,
                "unknown": 1,
            },
        )
        by_id = {item["resource_id"]: item for item in refs["referenced_resources"]}
        self.assertEqual(by_id["001-00001.SHP"]["match_status"], "resolved_payload")
        self.assertEqual(
            by_id["001-00001.SHP"]["resource_resolution_evidence"]["signals"],
            ["matched_shp_payload_by_basename"],
        )
        self.assertEqual(
            by_id["001-00001.SHP"]["resource_resolution_evidence"]["payload_provenance"],
            {
                "source_path": "legal-assets/derived/w16-ui-resource-import/hsl/drive_at/shape/001-00001.shp",
                "derived_root": "legal-assets/derived/w16-ui-resource-import",
                "archive_relpath": "hsl/drive_at/shape/001-00001.shp",
                "drive_relpath": "shape/001-00001.shp",
                "basename_match_key": "001-00001.shp",
                "evidence_tier": "resource_imported",
            },
        )
        self.assertEqual(by_id["001-00001.SHP"]["resource_category"], "actor_sprite")
        self.assertIn("obj_process_code:defProcPlayerInstall", by_id["001-00001.SHP"]["category_evidence"]["signals"])
        self.assertEqual(by_id["001-00001.SHP"]["payload"]["dimensions"], {"width": 32, "height": 48})
        self.assertEqual(by_id["001-00001.SHP"]["payload"]["row_coverage"], {"min": 12, "max": 32})
        self.assertEqual(by_id["001-00001.SHP"]["payload"]["row_segment_shape"]["common_segment_counts"][0], {"count": 1, "rows": 40})
        self.assertEqual(
            by_id["001-00001.SHP"]["payload"]["visual_profile"],
            {
                "classification": "partial_row_sprite",
                "extent_class": "medium_sprite",
                "width": 32,
                "height": 48,
                "area_pixels": 1536,
                "coverage_ratio_range": {"min": 0.375, "max": 1.0},
                "row_segment_complexity": "mostly_single_segment",
                "transparent_pixel_model": "row_gap_transparency_candidate",
                "atlas_padding_pixels_candidate": 1,
                "evidence_tier": "resource_parser_candidate",
                "unresolved_semantics": [
                    "visual profile is derived from SHP row coverage/segments only and is not animation frame semantics",
                    "transparent pixel model is inferred from missing row coverage, not from a proven palette or color key",
                ],
            },
        )
        self.assertEqual(
            by_id["001-00001.SHP"]["payload"]["color_key_evidence"],
            {
                "header_0x10_rgb565_hex": "0x0000",
                "header_0x10_value_seen_in_pixels": False,
                "present_pixel_count": 100,
                "transparent_gap_count": 1436,
                "top_rgb565_values": [],
                "semantic_status": "unresolved",
                "evidence_tier": "resource_parser_candidate",
                "unresolved_semantics": [
                    "header 0x10 is preserved as a color/key/flags candidate but not proven to be a transparent color",
                    "row gaps provide transparency candidates independently of any palette or color-key interpretation",
                ],
            },
        )
        self.assertEqual(by_id["001-00001.SHP"]["usage"]["object_codes"], ["6"])
        self.assertEqual(by_id["001-00001.SHP"]["usage"]["shape_number_candidates"], ["1"])
        self.assertEqual(by_id["001-00001.SHP"]["shape_number_evidence"]["semantic_status"], "unresolved")
        self.assertEqual(
            by_id["001-00001.SHP"]["shape_number_evidence"]["groups"],
            [
                {
                    "resource_category": "actor_sprite",
                    "process": "defProcPlayerInstall",
                    "role": "player_install",
                    "shape_number": "1",
                    "object_codes": ["6"],
                    "object_definition_count": 1,
                    "placed_instance_count": 1,
                    "candidate_kind": "numeric_literal",
                    "evidence_tier": "resource_ref_join",
                    "unresolved_semantics": [
                        "obj_shape_number value is grouped with process/resource usage but not interpreted as an animation frame",
                    ],
                }
            ],
        )
        self.assertEqual(by_id["tree07.SHP"]["resource_category"], "map_object")
        self.assertEqual(
            by_id["tree07.SHP"]["shape_number_evidence"]["groups"][0]["resource_category"],
            "map_object",
        )
        self.assertEqual(by_id["CURSOR01.SHP"]["resource_category"], "battle_ui")
        self.assertEqual(
            by_id["CURSOR01.SHP"]["shape_number_evidence"]["groups"][0]["process"],
            "defProcCursor",
        )
        ui_by_id = {item["resource_id"]: item for item in refs["battle_ui_resources"]}
        self.assertEqual(ui_by_id["CURSOR01.SHP"]["ui_group"], "cursor_or_selection")
        self.assertEqual(ui_by_id["CURSOR01.SHP"]["dimensions"], {"width": 16, "height": 16})
        self.assertEqual(ui_by_id["CURSOR01.SHP"]["shape_number_candidates"], ["3"])
        self.assertEqual(ui_by_id["CURSOR01.SHP"]["process_hints"], ["defProcCursor"])
        self.assertEqual(ui_by_id["CURSOR01.SHP"]["owner_semantics"]["semantic_status"], "unresolved")
        self.assertEqual(refs["summary"]["battle_ui_resource_count"], 1)
        self.assertEqual(refs["summary"]["battle_ui_group_counts"], {"cursor_or_selection": 1})
        self.assertEqual(by_id["AIR06_03.SHP"]["resource_category"], "magic_effect")
        self.assertEqual(by_id["024-00001.SHP"]["resource_category"], "actor_sprite")
        self.assertEqual(
            by_id["024-00001.SHP"]["shape_number_evidence"]["groups"][0]["candidate_kind"],
            "symbolic_or_expression",
        )
        self.assertEqual(
            refs["symbolic_shape_number_refs"],
            [
                {
                    "resource_id": "024-00001.SHP",
                    "resource_category": "actor_sprite",
                    "process": "defProcEnemy",
                    "role": "enemy",
                    "shape_number": "ENEMY024_Total",
                    "object_codes": ["32"],
                    "match_status": "resolved_payload",
                    "evidence_tier": "resource_ref_join",
                    "unresolved_semantics": [
                        "symbolic obj_shape_number is preserved as a candidate token and not evaluated to a frame count",
                    ],
                }
            ],
        )
        self.assertEqual(by_id["023-00001.SHP"]["match_status"], "unresolved_missing_payload")
        self.assertEqual(by_id["023-00001.SHP"]["resource_category"], "actor_sprite")
        self.assertIn(
            "not_found_in_current_imported_shp_payloads_by_basename",
            by_id["023-00001.SHP"]["resource_resolution_evidence"]["signals"],
        )
        self.assertEqual(
            by_id["023-00001.SHP"]["resource_resolution_evidence"]["searched_payload_roots"],
            [
                "legal-assets/derived/w16-ui-resource-import",
            ],
        )
        self.assertEqual(refs["unresolved_shape_refs"][0]["resource_id"], "023-00001.SHP")
        self.assertEqual(
            refs["unresolved_shape_refs"][0]["searched_payload_roots"],
            ["legal-assets/derived/w16-ui-resource-import"],
        )
        self.assertEqual(
            by_id["023-00001.SHP"]["shape_number_evidence"]["static_verification_questions"],
            [
                "Does the EXE read obj_shape_number as a SHP frame/image index, a resource variant id, or another object field?",
                "Which owner traversal consumes this object ref: UI object list, map object list, unit selectable list, or another runtime collection?",
            ],
        )
        self.assertEqual(by_id["UNKNOWN.SHP"]["resource_category"], "unknown")
        self.assertEqual(
            refs["summary"]["shape_number_candidate_kind_counts"],
            {"numeric_literal": 6, "symbolic_or_expression": 1},
        )
        self.assertEqual(
            refs["summary"]["visual_profile_class_counts"],
            {
                "full_rect_or_dense_sprite": 1,
                "partial_row_sprite": 4,
            },
        )
        self.assertEqual(
            refs["summary"]["color_header_0x10_counts"],
            {"0x0000": 5},
        )
        self.assertEqual(
            refs["summary"]["unresolved_shape_ref_reason_counts"],
            {"not_found_in_current_imported_shp_payloads_by_basename": 2},
        )
        self.assertEqual(refs["summary"]["audio_usage_hint_counts"], {"ui_confirm_or_accept": 1})
        self.assertEqual(refs["available_audio"][0]["source_id"], "Accept01.WAV")
        self.assertEqual(
            refs["available_audio"][0]["audio_profile"],
            {
                "channels": 1,
                "sample_rate": 22050,
                "bits_per_sample": 16,
                "frame_count": 2205,
                "duration_seconds": 0.1,
                "format_hint": "pcm_wav_after_xor_a8_header_normalization",
                "godot_import_hint": "AudioStreamWAV-compatible after header normalization",
                "evidence_tier": "resource_imported",
            },
        )
        self.assertEqual(refs["available_audio"][0]["usage_hint"]["category"], "ui_confirm_or_accept")
        self.assertEqual(refs["available_audio"][0]["trigger_semantics"]["semantic_status"], "unresolved")
        self.assertEqual(
            refs["available_audio"][0]["provenance"]["derived_root"],
            "legal-assets/derived/w12-first-chapter",
        )


if __name__ == "__main__":
    unittest.main()
