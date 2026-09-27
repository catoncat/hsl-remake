import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.skill_coverage import OUT, build


class SkillCoverageTests(unittest.TestCase):
    def test_generated_coverage_matches_source_and_reports_baseline(self):
        data = build()
        self.assertEqual(json.loads(OUT.read_text()), data)
        summary = data["summary"]
        self.assertEqual(summary["total"], 99)
        self.assertEqual(summary["learned_total"], 79)
        # Wave 9 lane A2 closed the source table: every MAGIC/SPECIAL row resolves and every
        # learned row is castable. Four unowned rows (高級金之手／百裂突刺2／獅子吼2／吸血劍2) are data-only.
        self.assertEqual(summary["supported"], 99)
        self.assertEqual(summary["learned_supported"], 79)
        self.assertEqual(summary["by_resolution"], {"ok": 99})
        unowned = {row["display_name"] for row in data["skills"] if not row["initial_owners"] and not row["learners"]}
        self.assertEqual(unowned, {"高級金之手", "百裂突刺", "獅子吼", "吸血劍"})
        self.assertEqual(summary["by_resolution"]["ok"], summary["supported"])
        self.assertEqual(sum(summary["by_resolution"].values()), summary["total"])
        self.assertEqual(summary["learned_by_resolution"]["ok"], summary["learned_supported"])
        self.assertEqual(sum(summary["learned_by_resolution"].values()), summary["learned_total"])
        self.assertEqual(set(summary["by_resolution"]) - {"ok", "unknown_skill"}, set())
        barrier = next(row for row in data["skills"] if row["display_name"] == "魔障壁")
        self.assertEqual(barrier["current_descriptor"]["damage_policy"], "native_magic_stat")
        self.assertEqual(barrier["current_descriptor"]["magic_key"], "resist_up")
        self.assertEqual([(item["job"], item["level"]) for item in barrier["learners"]], [("87", 48)])

    def test_job_up_tiers_learn_from_current_job_tables(self):
        data = build()
        tears = next(row for row in data["skills"] if row["display_name"] == "女神之淚")
        self.assertEqual([(item["job"], item["level"]) for item in tears["learners"]], [("86", 32), ("87", 32), ("82", 45)])
        moon = next(row for row in data["skills"] if row["display_name"] == "孤月斬")
        self.assertEqual({item["job"] for item in moon["learners"]}, {"80", "81", "82"})
        wrath = next(row for row in data["skills"] if row["display_name"] == "神怒")
        self.assertEqual(wrath["learners"], [{"job": "97", "level": None, "tier": 2, "attributes": {"str": 80, "dex": 40, "mind": 28, "con": 45}, "kind": "special"}])

    def test_early_learning_order_is_source_backed(self):
        data = build()
        self.assertIn("magic:magicWATER:magicCode06", data["learned_order"][:20])
        water = next(row for row in data["skills"] if row["id"] == "magic:magicWATER:magicCode06")
        self.assertEqual(water["learners"][0], {"job": "85", "level": 1, "kind": "magic"})
        self.assertEqual(water["current_resolution"], "ok")


if __name__ == "__main__":
    unittest.main()
