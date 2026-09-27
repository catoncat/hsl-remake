import json
import unittest
from pathlib import Path

from hsltools.levels.message_text import (SPEAKER_IDS, chapter_paths, check_message_text_evidence, level_message_ids, level_paths,
                                          seed_message_ids)
from hsltools.sources.tables import parse_table

ROOT = Path(__file__).resolve().parents[1]


class ChapterDialogueTests(unittest.TestCase):
    def test_parse_table_strips_color_controls_and_keeps_line_breaks(self):
        data = "[name]\r\nitem = 5,@1你好#世界@0\r\n[other]\r\nitem = 6,ignored\r\n".encode("cp950")
        self.assertEqual(parse_table(data), {"5": "你好\n世界"})

    def test_level52_message_ids_come_from_seed_scripts_and_speakers(self):
        seed = json.loads((ROOT / "content/generated/hsl/chapter01/battle052_seed.json").read_text(encoding="utf-8"))
        per_script = seed_message_ids(seed)
        self.assertEqual(per_script["story"], ["379", "380", "381", "383", "384", "385", "386", "387", "388", "389", "390", "391", "394"])
        self.assertEqual(per_script["winfail"], ["122", "378", "392", "393"])
        ids = level_message_ids(52, seed)
        self.assertEqual(ids[:3], ["0", "122", "305"])
        self.assertIn("382", ids)
        self.assertEqual(set(SPEAKER_IDS[52]), {"SID_PLAYER0", "SID_ENEMY021", "SID_ENEMY023", "SID_ENEMY024", "SID_ENEMY025", "SID_ENEMY026"})

    def test_tracked_evidence_matches_the_original_table(self):
        # The chapter-wide evidence keeps the hand-listed IDS (23); each level's own file
        # carries exactly the ids its seed scripts and speaker table name.
        chapter = check_message_text_evidence(ROOT / chapter_paths()["evidence"], None)
        self.assertEqual(chapter["message_id_count"], 23)
        for level, count in ((51, 21), (52, 23)):
            summary = check_message_text_evidence(ROOT / level_paths(level)["evidence"], level)
            self.assertEqual(summary["level"], level)
            self.assertEqual(summary["message_id_count"], count)

    def test_level51_evidence_names_the_messenger_speaker(self):
        evidence = json.loads((ROOT / level_paths(51)["evidence"]).read_text(encoding="utf-8"))
        self.assertEqual(evidence["speaker_names"]["10000"], "拉爾斯帝國兵")
        self.assertIn("provisional", evidence["speaker_name_policy"]["10000"])
        self.assertEqual(evidence["section_title"]["source_member"], "SHAPE01\\WORD051.SHP")

    def test_level52_speaker_labels_are_declared_with_policy(self):
        evidence = json.loads((ROOT / level_paths(52)["evidence"]).read_text(encoding="utf-8"))
        self.assertEqual(evidence["speaker_names"]["SID_ENEMY025"], "法蘭克")
        self.assertEqual(evidence["speaker_names"]["SID_ENEMY026"], "帝國法師")
        self.assertIn("provisional", evidence["speaker_name_policy"]["SID_ENEMY026"])
        self.assertEqual(evidence["section_title"]["source_member"], "SHAPE01\\WORD052.SHP")


if __name__ == "__main__":
    unittest.main()
