import tempfile
import unittest
from pathlib import Path

from PIL import Image

from tools.hsl_actor_walk_contact_sheet import CONTACT_SHEET_SCHEMA, build_contact_sheets
from hsltools.evidence.actor_walk_contact_sheet import check_contact_sheet_report


class ActorWalkContactSheetTests(unittest.TestCase):
    def test_contact_sheet_report_preserves_5x6_candidate_grid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            frames_dir = root / "frames" / "001"
            frames_dir.mkdir(parents=True)
            frames = []
            for facing in range(5):
                for pose in range(1, 7):
                    path = frames_dir / f"001-{facing}000{pose}.png"
                    image = Image.new("RGBA", (12 + pose, 16 + facing), (20 * pose, 30 * facing, 120, 255))
                    image.save(path)
                    frames.append(
                        {
                            "index": len(frames),
                            "actor_id": "001",
                            "png_path": path.as_posix(),
                            "facing_code": facing,
                            "pose_index": pose,
                            "tier": "resource-derived",
                        }
                    )
            manifest = {
                "schema": "hsl_actor_walk_manifest.v1",
                "actor_ids": ["001"],
                "actors": {
                    "001": {
                        "actor_id": "001",
                        "frame_count": 30,
                        "frames": frames,
                    }
                },
            }
            manifest_path = root / "actor_walk_manifest.json"
            manifest_path.write_text(__import__("json").dumps(manifest), encoding="utf-8")

            report = build_contact_sheets(manifest_path, root / "contact_sheets", ["001"])
            self.assertEqual(report["schema"], CONTACT_SHEET_SCHEMA)
            self.assertEqual(report["grid_contract"]["semantic_status"], "candidate_unconfirmed")
            actor = report["actors"]["001"]
            self.assertEqual(actor["row_count"], 5)
            self.assertEqual(actor["column_count"], 6)
            self.assertEqual(actor["frame_count"], 30)
            self.assertEqual(actor["missing_cells"], [])

            checked = check_contact_sheet_report(root / "contact_sheets" / "actor_walk_contact_sheet_manifest.json", ["001"])
            self.assertEqual(checked["actor_count"], 1)


if __name__ == "__main__":
    unittest.main()
