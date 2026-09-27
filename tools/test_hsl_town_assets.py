"""Offline unit tests for hsltools.assets.town_assets (no PAK needed)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import hsltools.assets.town_assets as town_assets  # noqa: E402


def _towndef() -> dict:
    return {
        "message_id_argument_positions": {"tePlayerMessage": [1], "teShapeMessage": [2], "teCheckMoney": [3], "teSelectInsertEvent": "even indexes from 2"},
        "town_events": [
            {
                "code": 9,
                "show_name": {"resource_id": 30, "text": "老闆"},
                "events": [
                    {"token": "teShapeMessage", "args": ["SHAPE\\FACE0062.SHP", "656", "858", "0"]},
                    {"token": "tePlayerMessage", "args": ["SID_雷歐納德", "859", "0"]},
                    {"token": "teCheckMoney", "args": ["100", "SHAPE\\FACE0073.SHP", "876", "1000"]},
                    {"token": "teSelectInsertEvent", "args": ["SID_雷歐納德", "2", "901", "10", "902", "11"]},
                    {"token": "teGetGold", "args": ["2000"]},
                ],
            }
        ],
    }


class ReferencedIdsTest(unittest.TestCase):
    def test_collects_messages_names_faces_and_players(self) -> None:
        refs = town_assets.referenced_ids(_towndef())
        # 606/607 are the shop engine's own refusal messages (ENGINE_MESSAGE_IDS), always included.
        self.assertEqual(refs["message_ids"], [606, 607, 858, 859, 901, 902, 1000])
        self.assertEqual(refs["name_ids"], [30, 656, 876])
        self.assertEqual(refs["faces"], ["SHAPE\\FACE0062.SHP", "SHAPE\\FACE0073.SHP"])
        self.assertEqual(refs["player_tokens"], ["SID_雷歐納德"])

    def test_players_by_name_resolves_resource_h_and_numeric_names(self) -> None:
        players = "[player]\nname = name_0\npicture = SHAPE\\FACE0000.SHP\n[player]\nname = 657\npicture = SHAPE\\FACE0058.SHP\n"
        rows = town_assets._players_by_name(players, {"0": "雷歐納德", "657": "克里歐司"}, {"name_0": 0})
        self.assertEqual(rows["雷歐納德"]["picture"], "SHAPE\\FACE0000.SHP")
        self.assertEqual(rows["克里歐司"]["row"], 2)


class OfflineCheckTest(unittest.TestCase):
    def test_tracked_outputs_are_consistent(self) -> None:
        self.assertEqual(town_assets.check_offline(town_assets.DEFAULT_OUTPUT_DIR), [])


if __name__ == "__main__":
    unittest.main()
