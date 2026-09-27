import copy
import json
import tempfile
import unittest
from pathlib import Path

import hsltools.checks.generated_metadata as generated_metadata


class GeneratedMetadataCheckTests(unittest.TestCase):
    def write_fixture(self, root: Path, *, mutate=None) -> Path:
        chapter = root / "content" / "generated" / "hsl" / "chapter01"
        chapter.mkdir(parents=True)
        source_policy = (
            "tracked compact metadata only; original payload text, images, audio, "
            "raw bytes, full hashes, and screenshots are not exported"
        )
        mechanics = {
            "schema": "hsl_chapter01_generated_metadata.v1",
            "source_policy": source_policy,
            "evidence_tier": "resource_parser_candidate",
            "unresolved_semantics": ["coordinates are candidates"],
            "map_grid": {
                "source_id": "level051.wrd",
                "dimensions": {"width": 2, "height": 2},
                "bytes_per_cell": 4,
                "size_matches_grid": True,
                "opaque_integrity": {
                    "cell_count": 4,
                    "flagged_cell_count": 1,
                    "unflagged_cell_count": 3,
                    "low24_range": {"min": 0, "max": 3},
                    "unique_cell_value_count": 4,
                    "low24_unique_cell_value_count": 4,
                    "low24_is_dense_cell_range": True,
                    "summary_semantics": "opaque structural WORL integrity summary derived from parser counts only; raw cell rows, raw cell values, terrain, blockers, and movement costs are not exported or decoded",
                },
                "semantics": "fixture grid",
            },
            "evef": {
                "source_id": "level051.bin",
                "record_count": 3,
                "non_zero_record_count": 2,
                "record_code_counts": {"6": 1, "96": 1},
                "record_layout": "fixture layout",
            },
            "object_records": {
                "source_id": "obj-051.obs",
                "object_count": 2,
                "resource_ref_count": 2,
            },
            "placement_role_counts": {"player_install": 1, "enemy": 1},
            "initial_placements": [
                {
                    "record_index": 1,
                    "object_code": 6,
                    "role": "player_install",
                    "process": "defProcPlayerInstall",
                    "shape_id": "001-00001.SHP",
                    "placement_x_candidate": 32,
                    "placement_y_candidate": 64,
                    "coordinate_semantics": "candidate",
                },
                {
                    "record_index": 2,
                    "object_code": 96,
                    "role": "enemy",
                    "process": "defProcEnemy",
                    "shape_id": "023-00001.SHP",
                    "placement_x_candidate": 96,
                    "placement_y_candidate": 128,
                    "coordinate_semantics": "candidate",
                },
            ],
            "placement_aggregates": {
                "summary_semantics": "counts derived from EVEF object-code joins only; coordinates, stats, terrain, and formulas remain unresolved",
                "role_counts": {"enemy": 1, "player_install": 1},
                "object_code_counts": {"6": 1, "96": 1},
                "process_counts": {"defProcEnemy": 1, "defProcPlayerInstall": 1},
                "shape_id_counts": {"001-00001.SHP": 1, "023-00001.SHP": 1},
                "by_role": {
                    "enemy": {
                        "object_code_counts": {"96": 1},
                        "process_counts": {"defProcEnemy": 1},
                        "shape_id_counts": {"023-00001.SHP": 1},
                    },
                    "player_install": {
                        "object_code_counts": {"6": 1},
                        "process_counts": {"defProcPlayerInstall": 1},
                        "shape_id_counts": {"001-00001.SHP": 1},
                    },
                },
            },
            "placement_join_integrity": {
                "summary_semantics": "count-only EVEF/object join coverage summary; object names, raw object fields, coordinates, stats, terrain, AI, and formulas remain unresolved",
                "evef_record_count": 3,
                "non_zero_record_count": 2,
                "joined_record_count": 2,
                "unmatched_record_count": 0,
                "placed_object_code_count": 2,
                "object_record_count": 2,
                "role_coverage_counts": {"enemy": 1, "player_install": 1},
            },
            "script_summary": {
                "story051": {
                    "source_id": "STORY051.TXT",
                    "section_counts": {"story": 1},
                    "action_counts": {
                        "actInsertFailStatus": 1,
                        "actInsertEventStatus": 4,
                        "actMessage": 1,
                        "actShowWinFailStatus": 1,
                    },
                },
                "winfail051": {
                    "source_id": "winfail051.txt",
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
                },
            },
            "status_action_contract": {
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
            "status_lifecycle_summary": {
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
        }
        files = {
            "index.json": {
                "schema": "hsl_chapter01_generated_index.v1",
                "source_policy": source_policy,
                "files": {
                    "mechanics": "mechanics.json",
                    "map_grid": "map_grid.json",
                    "initial_placements": "initial_placements.json",
                    "script_summary": "script_summary.json",
                },
            },
            "mechanics.json": mechanics,
            "map_grid.json": {
                "schema": "hsl_chapter01_map_grid.v1",
                "source_policy": source_policy,
                "evidence_tier": "resource_parser_candidate",
                "map_grid": copy.deepcopy(mechanics["map_grid"]),
            },
            "initial_placements.json": {
                "schema": "hsl_chapter01_initial_placements.v1",
                "source_policy": source_policy,
                "evidence_tier": "resource_parser_candidate",
                "unresolved_semantics": ["coordinates are candidates"],
                "placement_role_counts": copy.deepcopy(mechanics["placement_role_counts"]),
                "placement_aggregates": copy.deepcopy(mechanics["placement_aggregates"]),
                "placement_join_integrity": copy.deepcopy(mechanics["placement_join_integrity"]),
                "initial_placements": copy.deepcopy(mechanics["initial_placements"]),
            },
            "script_summary.json": {
                "schema": "hsl_chapter01_script_summary.v1",
                "source_policy": source_policy,
                "evidence_tier": "resource_parser_candidate",
                "script_summary": copy.deepcopy(mechanics["script_summary"]),
                "status_action_contract": copy.deepcopy(mechanics["status_action_contract"]),
                "status_lifecycle_summary": copy.deepcopy(mechanics["status_lifecycle_summary"]),
            },
        }
        if mutate:
            mutate(files)
        for name, data in files.items():
            (chapter / name).write_text(json.dumps(data, indent=2), encoding="utf-8")
        return chapter

    def test_valid_fixture_passes_consistency_and_forbidden_field_checks(self):
        with tempfile.TemporaryDirectory() as tmp:
            chapter = self.write_fixture(Path(tmp))

            errors = generated_metadata.check_chapter_dir(chapter)

        self.assertEqual(errors, [])

    def test_detects_map_grid_mismatch_between_mechanics_and_split_file(self):
        def mutate(files):
            files["map_grid.json"]["map_grid"]["dimensions"]["width"] = 3

        with tempfile.TemporaryDirectory() as tmp:
            chapter = self.write_fixture(Path(tmp), mutate=mutate)

            errors = generated_metadata.check_chapter_dir(chapter)

        self.assertTrue(any("map_grid" in error for error in errors), errors)

    def test_detects_forbidden_raw_private_fields_recursively(self):
        def mutate(files):
            files["script_summary.json"]["script_summary"]["story051"]["raw_bytes"] = "00ff"

        with tempfile.TemporaryDirectory() as tmp:
            chapter = self.write_fixture(Path(tmp), mutate=mutate)

            errors = generated_metadata.check_chapter_dir(chapter)

        self.assertTrue(any("raw_bytes" in error for error in errors), errors)

    def test_detects_placement_aggregate_drift(self):
        def mutate(files):
            files["initial_placements.json"]["placement_aggregates"]["by_role"]["enemy"]["object_code_counts"]["99"] = 1

        with tempfile.TemporaryDirectory() as tmp:
            chapter = self.write_fixture(Path(tmp), mutate=mutate)

            errors = generated_metadata.check_chapter_dir(chapter)

        self.assertTrue(any("placement_aggregates" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
