import json
import tempfile
import unittest
from pathlib import Path

import hsltools.data.scope_inventory as inv
from hsltools import original_content


class ScopeInventoryTests(unittest.TestCase):
    def test_classify_level_ranges(self):
        self.assertEqual(inv.classify_level(1), "main")
        self.assertEqual(inv.classify_level(99), "main")
        self.assertEqual(inv.classify_level(501), "battle_stub_500")
        self.assertEqual(inv.classify_level(901), "special_900")
        self.assertEqual(inv.classify_level(250), "other")

    def test_section_and_message_counting_skips_comments(self):
        text = "#include X.H\n[magic]\ncode = 1\n;[magic]\n [magic] \n[special]\n"
        self.assertEqual(inv.count_sections(text, "magic"), 2)
        self.assertEqual(inv.count_sections_by_name(text), {"magic": 2, "special": 1})
        story = "actMessage,SID_PLAYER0,1,1\n;actMessage,SID_PLAYER0,1,2\nactMessageIfExist,SID_X,1,3\n"
        self.assertEqual(inv.count_messages(story), 1)

    def test_summarize_levels_separates_battles_and_story_only(self):
        levels = {
            1: {"level": 1, "range": "main", "story": True, "winfail": True, "level_bin": True, "story_messages": 3},
            2: {"level": 2, "range": "main", "story": True, "winfail": False, "level_bin": True, "story_messages": 2},
            3: {"level": 3, "range": "main", "story": False, "winfail": False, "level_bin": True, "story_messages": 0},
            501: {"level": 501, "range": "battle_stub_500", "story": True, "winfail": True, "level_bin": True, "story_messages": 0},
        }
        summary = inv.summarize_levels(levels)
        self.assertEqual(summary["main"]["levels"], 3)
        self.assertEqual(summary["main"]["battles"], 1)
        self.assertEqual(summary["main"]["story_only"], 1)
        self.assertEqual(summary["main"]["story_messages"], 5)
        self.assertEqual(summary["battle_stub_500"]["battles"], 1)

    def test_remake_coverage_reads_campaign_and_scenarios(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "content/battles").mkdir(parents=True)
            (root / "content/battles/a.json").write_text(json.dumps({"id": "a", "status": "mechanics-playable-provisional"}), encoding="utf-8")
            (root / "content/battles/b.json").write_text(json.dumps({"id": "b", "status": "opening-preview-provisional", "level_kind": "story"}), encoding="utf-8")
            (root / "content/battles/c.json").write_text(json.dumps({"id": "c", "status": "story-scene-provisional", "level_kind": "story"}), encoding="utf-8")
            campaign = root / "content/battles/campaign.json"
            campaign.write_text(
                json.dumps(
                    {
                        "battles": {
                            "51": {"scenario": "res://content/battles/a.json", "title": "A"},
                            "53": {"scenario": "res://content/battles/b.json", "title": "B", "kind": "story"},
                            "58": {"scenario": "res://content/battles/c.json", "title": "C", "kind": "story"},
                        }
                    }
                ),
                encoding="utf-8",
            )
            coverage = inv.remake_coverage(campaign, root=root)
        self.assertEqual(coverage["registered_levels"], [51, 53, 58])
        self.assertEqual(coverage["counts"], {"registered": 3, "battle_scenarios": 1, "story_only_scenes": 1, "opening_previews": 1})
        self.assertEqual(coverage["entries"][1]["scenario_id"], "b")

    @unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
    def test_tracked_inventory_is_consistent_offline(self):
        self.assertTrue(inv.DEFAULT_OUTPUT.exists())
        self.assertEqual(inv.check(inv.DEFAULT_OUTPUT, None, inv.DEFAULT_CAMPAIGN), 0)


if __name__ == "__main__":
    unittest.main()
