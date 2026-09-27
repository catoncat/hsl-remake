import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from hsltools.data import battle_rewards as rewards  # the generator module (patched attributes must be its own)
from hsltools.sources.tables import authored_characters


class BattleRewardSourceTests(unittest.TestCase):
    def test_tracked_join_preserves_order_duplicates_and_source_limits(self):
        payload = rewards.build()
        self.assertEqual(payload["actors"]["024"]["carry_items"], [241, 241, 247, 248, 201])
        self.assertEqual(payload["actors"]["021"]["gold"], 100)
        self.assertEqual(payload["actors"]["026"]["gold"], 120)
        self.assertEqual(payload["actors"]["025"]["gold"], 500)
        self.assertFalse(payload["actors"]["001"]["carry_list_declared"])
        self.assertEqual(payload["actors"]["001"]["carry_items"], [])
        self.assertEqual(payload["evidence_tier"], "resource-derived")
        self.assertTrue(payload["live"])

    def test_every_players_character_row_is_compiled(self):
        payload = rewards.build()
        # 66 PLAYERS.TXT rows plus the authored characters (content/authored/roles/characters.json).
        self.assertEqual(len(payload["actors"]), 66 + len(authored_characters()))
        self.assertLessEqual({code.zfill(3) for code in rewards.REQUIRED_ACTORS}, set(payload["actors"]))
        # Monsters of the upcoming formal battles and encounters carry their PLAYERS gold and TOWNDEF lists.
        self.assertEqual(payload["actors"]["038"]["gold"], 80)
        self.assertEqual(payload["actors"]["038"]["carry_items"], [])
        self.assertEqual(payload["actors"]["049"]["gold"], 700)
        self.assertEqual(payload["actors"]["049"]["carry_list_id"], 46)
        self.assertEqual(payload["actors"]["049"]["carry_items"], [242, 244, 258, 259, 260, 221, 240])
        self.assertEqual(payload["actors"]["057"]["carry_list_id"], 0)
        self.assertTrue(payload["actors"]["057"]["carry_list_declared"])
        self.assertIn("gold_note", payload["actors"]["100"])
        self.assertTrue(all(actor["status_raw"] == 0 for actor in payload["actors"].values()))
        curated = json.loads(rewards.CARRY.read_text(encoding="utf-8"))
        wanted = {str(actor["carry_list_id"]) for actor in payload["actors"].values() if actor["carry_list_id"]}
        self.assertEqual(set(curated["lists"]), wanted)

    def test_duplicate_and_missing_actor_templates_are_rejected(self):
        rows = rewards.actor_rows()
        for malformed in (rows + [rows[0]], rows[1:]):
            with self.subTest(count=len(malformed)), patch.object(rewards, "character_rows", return_value=malformed):
                with self.assertRaisesRegex(ValueError, "Duplicate reward actor|Incomplete battle reward"):
                    rewards.actor_rows()

    def test_carry_import_keeps_duplicates_and_rejects_ambiguous_or_missing_lists(self):
        raw = b"[item]\ncode=29\nitem_id=241,241,247,248,201\n"
        self.assertEqual(rewards.carry_lists(raw, {29}), {"29": [241, 241, 247, 248, 201]})
        with self.assertRaisesRegex(ValueError, "Duplicate carry list"):
            rewards.carry_lists(raw + raw, {29})
        with self.assertRaisesRegex(ValueError, "Incomplete carry lists"):
            rewards.carry_lists(raw, {29, 30})

    def test_corrupt_curated_lists_are_rejected(self):
        original = json.loads(rewards.CARRY.read_text(encoding="utf-8"))
        with tempfile.TemporaryDirectory() as folder:
            carry = Path(folder) / "carry_items.json"
            for value in (None, [], "241", [True], [999999]):
                curated = json.loads(json.dumps(original))
                if value is None:
                    del curated["lists"]["29"]
                else:
                    curated["lists"]["29"] = value
                carry.write_text(json.dumps(curated), encoding="utf-8")
                with self.subTest(value=value), patch.object(rewards, "CARRY", carry):
                    with self.assertRaisesRegex(ValueError, "carry list|Carry list"):
                        rewards.build()

    def test_duplicate_item_codes_are_rejected(self):
        parse = rewards.blocks

        def duplicate_item(raw, section):
            rows = parse(raw, section)
            return rows + [rows[0]] if section == "item" else rows

        with patch.object(rewards, "blocks", side_effect=duplicate_item):
            with self.assertRaisesRegex(ValueError, "Duplicate item code"):
                rewards.build()

    def test_stale_check_fails_without_rewriting_data(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "rewards.json"
            output.write_text('{"stale": true}\n', encoding="utf-8")
            before = output.read_bytes()
            with patch.object(rewards, "OUTPUT", output):
                with self.assertRaisesRegex(ValueError, "Stale battle reward data"):
                    rewards.main(["--check"])
            self.assertEqual(output.read_bytes(), before)

    def test_original_source_mismatch_is_not_silently_reimported(self):
        before = rewards.CARRY.read_bytes()
        with patch.object(rewards, "curate_carry", return_value={"different": True}):
            with self.assertRaisesRegex(ValueError, "Original carry source differs"):
                rewards.main(["--check", "--pak", "unused.pak"])
        self.assertEqual(rewards.CARRY.read_bytes(), before)

    def test_read_only_check_refuses_import(self):
        with patch.object(rewards, "curate_carry") as curate:
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
                rewards.main(["--check", "--import-carry", "--pak", "unused.pak"])
            self.assertEqual(raised.exception.code, 2)
            curate.assert_not_called()


if __name__ == "__main__":
    unittest.main()
