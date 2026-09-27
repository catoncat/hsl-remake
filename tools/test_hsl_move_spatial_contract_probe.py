import json
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

from tools.hsl_move_spatial_contract_probe import SCHEMA, build_probe_report
from tools.hsl_move_spatial_contract_probe_check import check_probe_report


class MoveSpatialContractProbeTests(unittest.TestCase):
    def test_probe_reports_mismatch_without_claiming_parity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            original = root / "original_move.png"
            godot = root / "godot_move.png"
            _draw_grid(original, (200, 200), (40, 30), 6, 5, 20)
            _draw_grid(godot, (200, 200), (95, 120), 2, 2, 18)

            manifest = {
                "schema": "hsl_first_battle_visual_evidence_index.v1",
                "evidence": [
                    {
                        "id": "move_overlay_primary",
                        "file": "original_move.png",
                        "status": "confirmed",
                        "evidence_tier": "runtime-measured",
                        "visual_state": "Move command selected; blue movement range overlay visible",
                        "use_for": ["primary original-runtime Move overlay baseline"],
                        "not_for": ["full movement cost formula"],
                    }
                ],
            }
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            report = build_probe_report(
                repo_root=root,
                evidence_manifest=manifest_path,
                original_evidence_id="move_overlay_primary",
                godot_capture=godot,
                min_component_area=1,
            )
            self.assertEqual(report["schema"], SCHEMA)
            self.assertEqual(report["comparison"]["status"], "mismatch_provisional")
            self.assertIn("does not prove", report["claim_limit"])
            self.assertGreater(report["original"]["image"]["significant_component_count"], 0)
            self.assertGreater(report["godot"]["image"]["significant_component_count"], 0)

            report_path = root / "probe.json"
            report_path.write_text(json.dumps(report), encoding="utf-8")
            checked = check_probe_report(report_path, root)
            self.assertEqual(checked["status"], "mismatch_provisional")


def _draw_grid(path: Path, size: tuple[int, int], origin: tuple[int, int], columns: int, rows: int, pitch: int) -> None:
    image = Image.new("RGBA", size, (30, 50, 55, 255))
    draw = ImageDraw.Draw(image)
    x0, y0 = origin
    for row in range(rows):
        for column in range(columns):
            x = x0 + column * pitch
            y = y0 + row * pitch
            draw.rectangle((x, y, x + pitch - 3, y + pitch - 3), outline=(2, 57, 252, 255), width=2)
    image.save(path)


if __name__ == "__main__":
    unittest.main()
