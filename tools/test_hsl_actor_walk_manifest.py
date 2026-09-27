import struct
import tempfile
import unittest
from pathlib import Path

from hsltools.sources.actor_walk_frames import (
    ACTOR_WALK_SCHEMA,
    build_actor_walk_manifest,
    expected_walk_record_name,
    parse_walk_record_name,
)


class ActorWalkManifestTests(unittest.TestCase):
    def test_expected_walk_record_names_support_multi_digit_shape_counts(self):
        self.assertEqual(expected_walk_record_name("001", 0, 1), "@:\\shape\\001-00001.shp")
        self.assertEqual(expected_walk_record_name("001", 4, 6), "@:\\shape\\001-40006.shp")
        self.assertEqual(expected_walk_record_name("025", 0, 13), "@:\\shape\\025-00013.shp")

    def test_parse_walk_record_name_rejects_non_walk_actor_resources(self):
        self.assertEqual(
            parse_walk_record_name("@:\\shape\\001-30004.shp"),
            {"actor_id": "001", "facing_code": 3, "pose_index": 4},
        )
        self.assertEqual(
            parse_walk_record_name("@:\\shape\\025-00013.shp"),
            {"actor_id": "025", "facing_code": 0, "pose_index": 13},
        )
        self.assertIsNone(parse_walk_record_name("@:\\shape\\001-P.SHP"))
        self.assertIsNone(parse_walk_record_name("@:\\shape\\001-M0001.SHP"))
        self.assertIsNone(parse_walk_record_name("@:\\magic\\001-00001.SHP"))

    def test_manifest_records_frames_and_fallback_without_decoding_when_requested(self):
        records = {
            expected_walk_record_name("001", facing, pose): b"TLHS" + bytes(24) + struct.pack("<ii", 11, 49)
            for facing in range(5)
            for pose in range(1, 7)
        }
        with tempfile.TemporaryDirectory() as tmp:
            output_root = Path(tmp) / "actor_walk_frames"
            manifest = build_actor_walk_manifest(
                ["001"],
                records,
                output_root,
                decode_png=False,
                res_root="res://content/imported/hsl/chapter01/actor_walk_frames",
            )

        self.assertEqual(manifest["schema"], ACTOR_WALK_SCHEMA)
        self.assertEqual(manifest["evidence_tier"], "resource-derived")
        actor = manifest["actors"]["001"]
        self.assertEqual(actor["frame_count"], 30)
        self.assertEqual(actor["frames"][0]["draw_origin"], [11, 49])
        self.assertEqual(actor["fallback"]["src"], "res://content/imported/hsl/chapter01/actor_walk_frames/001/001-00001.png")
        self.assertEqual(actor["animations"]["walk"]["down"]["frames"], [6, 7, 8, 9, 10, 11])
        self.assertEqual(actor["animations"]["idle"]["0"]["frames"], [0, 1, 2, 3, 4, 5])


if __name__ == "__main__":
    unittest.main()
