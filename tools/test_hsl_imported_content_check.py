import json
import tempfile
import unittest
from pathlib import Path

import hsltools.checks.imported_content as checker


class ImportedContentCheckTests(unittest.TestCase):
    def make_root(self) -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name) / "chapter01"
        root.mkdir()

        def write(name, value):
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value), encoding="utf-8")

        for relative in [
            "shape_previews/actor_sprite/001-00001.SHP.png",
            "shape_previews/actor_sprite/021-00001.SHP.png",
            "shape_previews/actor_sprite/023-00001.SHP.png",
            "shape_previews/actor_sprite/024-00001.SHP.png",
            "shape_previews/actor_sprite/026-00001.SHP.png",
            "shape_previews/map_object/tree07.SHP.png",
            "shape_previews/map_object/FIRE01-01.SHP.png",
            "shape_previews/map_object/bar004a.SHP.png",
            "shape_previews/map_object/bar004b.SHP.png",
            "shape_previews/battle_ui/BCMD01_1.SHP.png",
        ]:
            path = root.parent / "shared" / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"png")
        wav = root / "audio_normalized/Accept01.WAV"
        wav.parent.mkdir(parents=True, exist_ok=True)
        wav.write_bytes(b"RIFFtest")

        shape_entries = []
        for actor in checker.EXPECTED_ACTORS:
            shape_entries.append({
                "resource_id": f"{actor}-00001.SHP",
                "category": "actor_sprite",
                "preview_res_path": f"res://content/imported/hsl/shared/shape_previews/actor_sprite/{actor}-00001.SHP.png",
            })
        write("shape_preview_index.json", {
            "schema": checker.EXPECTED_SCHEMAS["shape_preview_index.json"],
            "entries": shape_entries,
        })
        write("ui_preview_index.json", {
            "schema": checker.EXPECTED_SCHEMAS["ui_preview_index.json"],
            "entries": [{
                "resource_id": "BCMD01_1.SHP",
                "ui_group": "battle_command_icon",
                "preview_res_path": "res://content/imported/hsl/shared/shape_previews/battle_ui/BCMD01_1.SHP.png",
            }],
        })
        placements = []
        for shape, count in checker.EXPECTED_MAP_OBJECT_SHAPES.items():
            placements.extend({
                "role": "map_object",
                "shape_resource_id": shape,
                "join": {"status": "joined"},
                "coordinate_interpretation": {"interpretation_status": "provisional"},
            } for _ in range(count))
        write("map_objects.json", {
            "schema": checker.EXPECTED_SCHEMAS["map_objects.json"],
            "placements": placements,
        })
        curated = Path("docs/evidence_packets/runtime_observations/first_battle_visuals")
        # The checker intentionally requires real curated paths. Point fixtures to
        # existing repository evidence rather than synthesizing a fake authority.
        sources = [
            (curated / "p1_route_upper_formation_11.png").as_posix(),
            (curated / "p1_route_upper_formation_12.png").as_posix(),
        ]
        write("map_object_alignment.json", {
            "schema": checker.EXPECTED_SCHEMAS["map_object_alignment.json"],
            "shapes": {shape: {"draw_origin": [0, 0]} for shape in checker.EXPECTED_MAP_OBJECT_SHAPES},
            "calibrations": [
                {"record_index": 8, "evidence_tier": "runtime-measured", "anchor_source_files": sources},
                {"record_index": 13, "evidence_tier": "runtime-measured", "anchor_source_files": sources},
            ],
        })
        visibility = []
        for resource_id in checker.EXPECTED_MAP_OBJECT_SHAPES:
            visibility.append({
                "resource_id": resource_id,
                "display_preview": {
                    "preview_res_path": f"res://content/imported/hsl/shared/shape_previews/map_object/{resource_id}.png"
                },
            })
        write("map_object_visibility_evidence.json", {
            "schema": checker.EXPECTED_SCHEMAS["map_object_visibility_evidence.json"],
            "objects": visibility,
        })
        write("audio_normalized.json", {
            "schema": checker.EXPECTED_SCHEMAS["audio_normalized.json"],
            "normalized_audio": [{
                "normalized_res_path": "res://content/imported/hsl/chapter01/audio_normalized/Accept01.WAV",
                "trigger_semantics_status": "unresolved",
            }],
        })
        scripts = []
        for script_id in checker.EXPECTED_SCRIPTS:
            write(f"scripts/{script_id}.json", {"schema": "hsl_chapter01_script_ir.v1", "id": script_id})
            scripts.append({
                "id": script_id,
                "path": f"res://content/imported/hsl/chapter01/scripts/{script_id}.json",
            })
        write("script_ir_index.json", {
            "schema": checker.EXPECTED_SCHEMAS["script_ir_index.json"],
            "scripts": scripts,
        })
        events = [{"kind": "opening_music"}]
        events.extend({"kind": "opening_message"} for _ in range(17))
        events.append({"kind": "actor_walk_disp_wait"})
        events.append({"kind": "first_control_marker"})
        write("opening_timeline.json", {
            "schema": checker.EXPECTED_SCHEMAS["opening_timeline.json"],
            "events": events,
        })
        return root

    def test_valid_current_imports(self):
        summary = checker.check_imported_content(self.make_root())
        self.assertEqual(summary["opening_event_count"], 20)
        self.assertEqual(summary["audio_count"], 1)

    def test_missing_preview_fails(self):
        root = self.make_root()
        (root.parent / "shared/shape_previews/actor_sprite/001-00001.SHP.png").unlink()
        with self.assertRaisesRegex(checker.CheckFailure, "missing/empty preview"):
            checker.check_imported_content(root)

    def test_map_object_count_drift_fails(self):
        root = self.make_root()
        path = root / "map_objects.json"
        data = json.loads(path.read_text())
        data["placements"].pop()
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(checker.CheckFailure, "shape counts mismatch"):
            checker.check_imported_content(root)


if __name__ == "__main__":
    unittest.main()
