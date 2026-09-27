import re
import unittest
from pathlib import Path
from unittest.mock import patch

from hsltools.data.combat_aftermath import build
from hsltools.sources.tables import TABLES, blocks, character_rows


class CombatAftermathSourceTests(unittest.TestCase):
    def test_template_speaker_and_nonzero_variants(self):
        actors = build()["actors"]
        self.assertEqual(actors["001"]["messages"], [])  # Script owns Leonard's line.
        self.assertEqual([line["id"] for line in actors["021"]["messages"]], ["372", "373"])
        self.assertEqual([line["id"] for line in actors["023"]["messages"]], ["374", "375"])
        self.assertEqual([line["id"] for line in actors["025"]["messages"]], ["395"])
        self.assertEqual(actors["021"]["speaker"], "拉爾斯帝國兵")
        self.assertEqual(actors["026"]["speaker"], "帝國法師")
        self.assertNotEqual(actors["023"]["speaker"], actors["024"]["speaker"])
        self.assertEqual(actors["021"]["messages"][0]["text"], "拉爾斯帝國萬歲！！")

    def test_every_players_row_is_declared_and_party_speaker_resolves(self):
        data = build()
        actors = data["actors"]
        # Every PLAYERS.TXT row plus the authored characters (content/authored/roles/characters.json).
        self.assertEqual(set(actors), {row["code"].zfill(3) for row in character_rows()})
        battle_actor_ids = set()
        for path in Path("content/battles").glob("*.json"):
            battle_actor_ids |= set(re.findall(r'"actor_id": "(\d+)"', path.read_text(encoding="utf-8")))
        self.assertTrue(battle_actor_ids <= set(actors), sorted(battle_actor_ids - set(actors)))
        # 咕嚕 (008) has a dead_message but no job_show_name: its speaker is its own party name.
        self.assertEqual(actors["008"]["speaker"], "咕嚕")
        self.assertEqual([line["id"] for line in actors["008"]["messages"]], ["1825"])
        self.assertEqual(actors["049"]["speaker"], "魔騎士")
        self.assertIn("005", data["silent_actors"])
        self.assertNotIn("049", data["silent_actors"])
        for code in data["silent_actors"]:
            self.assertEqual(actors[code]["messages"], [])

    def test_missing_referenced_text_fails_before_generating(self):
        with patch("hsltools.data.combat_aftermath.parse_table", return_value={}):
            with self.assertRaises(KeyError):
                build()


if __name__ == "__main__":
    unittest.main()
