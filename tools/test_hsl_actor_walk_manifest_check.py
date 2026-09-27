import json
import tempfile
import unittest
from pathlib import Path

from hsltools.evidence.actor_walk_manifest import check_actor_walk_manifest


class ActorWalkManifestCheckTests(unittest.TestCase):
    def test_checker_accepts_complete_manifest_with_existing_pngs(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            frames = []
            for index in range(30):
                path = root / "001" / f"001-{index:05d}.png"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00" * 24)
                frames.append({
                    "index": index,
                    "source_member": f"@:\\shape\\001-00001.shp",
                    "png_path": path.as_posix(),
                    "res_path": f"res://fake/{index}.png",
                    "facing_code": index // 6,
                    "pose_index": (index % 6) + 1,
                    "tier": "resource-derived",
                })
            manifest = {
                "schema": "hsl_actor_walk_manifest.v1",
                "evidence_tier": "resource-derived",
                "actors": {
                    "001": {
                        "actor_id": "001",
                        "frame_count": 30,
                        "expected_frame_count": 30,
                        "frames": frames,
                        "animations": {
                            "idle": {"0": {"frames": list(range(0, 6))}},
                            "walk": {name: {"frames": list(range(code * 6, code * 6 + 6))} for name, code in {"up": 3, "down": 1, "left": 4, "right": 2}.items()},
                        },
                        "fallback": {"src": frames[0]["res_path"]},
                        "unresolved": ["facing_semantics_unconfirmed"],
                    }
                },
            }
            manifest_path = root / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

            summary = check_actor_walk_manifest(manifest_path, ["001"])

        self.assertEqual(summary["actor_count"], 1)
        self.assertEqual(summary["frame_count"], 30)


if __name__ == "__main__":
    unittest.main()
