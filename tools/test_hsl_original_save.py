"""Offline unit tests for hsltools.data.original_save: the level-entry 回憶錄 (a save that loads
into a level that is not a big-map point) generates, reads back through the codec and carries
the actSetNextPlayLevelEvent header words; big-map presets keep level_files 49."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(ROOT / "tools"))

from hsltools.data import original_save as save_module  # noqa: E402
from hsltools.data.original_save import BIG_MAP_LEVEL, PRESETS, OriginalSave, apply_spec, load_sample  # noqa: E402
from hsltools.data.original_save_members import RECORD_COUNT, RECORD_SIZE, REC, i32, learned_skill_bit  # noqa: E402


class LevelEntrySaveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.base = load_sample()
        cls.save, cls.receipt = apply_spec(cls.base, PRESETS["level53_pre_battle"])
        cls.raw = cls.save.serialize()

    def test_round_trip_through_codec(self) -> None:
        again = OriginalSave.parse(self.raw)
        self.assertEqual(again.serialize(), self.raw)
        self.assertEqual(again.header, self.save.header)
        self.assertIsNone(again.battle_tail)

    def test_header_holds_the_winfail052_next_level_words(self) -> None:
        header = OriginalSave.parse(self.raw).header
        self.assertEqual((header["next_level"], header["level_files"], header["current_level"]), (58, 58, 58))
        self.assertNotEqual(header["level_files"], BIG_MAP_LEVEL)
        self.assertEqual(header["walk_from_point"], -1)
        self.assertEqual(header["walk_to_point"], 0)
        self.assertEqual(header["current_point"], 1)   # list-row point name (歐姆村)
        self.assertEqual(header["leonard_level"], 1)
        self.assertEqual(self.receipt["entry_level"], 58)
        self.assertEqual(self.receipt["applied_flow"], ["winfail51:win", "winfail52:win"])
        self.assertEqual(self.receipt["skipped_tokens"],
                         ["winfail51:actSetNextPlayLevelEvent", "winfail51:actSetNextPlayLevelEvent", "winfail52:actSetNextPlayLevelEvent"])

    def test_only_leonard_is_registered_and_tina_record_is_never_initialised(self) -> None:
        again = OriginalSave.parse(self.raw)
        self.assertEqual(again.slot_code(0), 800)
        self.assertEqual([slot for slot in range(21) if again.slot_code(slot)], [0])
        self.assertEqual(i32(again.record(0), REC["code"]), 1)
        # 0x407ec0 copies the PLAYERS 002 template into live index 2 only while +0x4c..+0x58 are zero
        tina = again.record(1)
        self.assertEqual(bytes(tina), bytes(RECORD_SIZE))
        for index in range(RECORD_COUNT):
            if index != 1:
                self.assertEqual(bytes(again.players[index * RECORD_SIZE:(index + 1) * RECORD_SIZE]), bytes(RECORD_SIZE), index)

    def test_big_map_presets_keep_the_big_map_level_files(self) -> None:
        for name, spec in PRESETS.items():
            if "entry_level" in spec:
                continue
            header = apply_spec(self.base, spec)[0].header
            self.assertEqual(header["level_files"], BIG_MAP_LEVEL, name)
            self.assertEqual(header["next_level"], spec["point"], name)

    def test_entry_level_and_point_are_exclusive(self) -> None:
        spec = dict(PRESETS["level53_pre_battle"], point=1)
        with self.assertRaises(ValueError):
            apply_spec(self.base, spec)

    def test_level05_preset_stands_at_milando_with_the_carried_party(self) -> None:
        save, receipt = apply_spec(self.base, PRESETS["level05_pre_battle"])
        again = OriginalSave.parse(save.serialize())
        self.assertEqual((again.header["next_level"], again.header["level_files"]), (4, BIG_MAP_LEVEL))
        self.assertEqual(receipt["point"]["id"], 4)
        self.assertEqual([slot for slot in range(21) if again.slot_code(slot)], [0, 1, 2, 3])
        self.assertEqual([i32(again.record(slot), REC["level"]) for slot in range(4)], [7, 4, 6, 7])
        self.assertEqual([member["max_hp"] for member in receipt["party"]], [39, 38, 42, 50])
        self.assertEqual(again.header["leonard_level"], 7)

    def test_level06_preset_stands_in_sheeda_with_the_tavern_soldier_and_learned_skills(self) -> None:
        save, receipt = apply_spec(self.base, PRESETS["level06_pre_battle"])
        again = OriginalSave.parse(save.serialize())
        self.assertEqual((again.header["next_level"], again.header["level_files"]), (6, BIG_MAP_LEVEL))
        self.assertEqual(receipt["towns"]["6"], {"tree": {"0": [16, 17, 18, 20], "20": [21, 22, 23]}, "exec_event": 19})
        self.assertEqual([i32(again.record(slot), REC["level"]) for slot in range(4)], [8, 5, 7, 8])
        self.assertEqual(i32(again.record(1), REC["magic_words"] + 4) & 0x1, 0x1)  # 水剎: water word, bit 0
        self.assertEqual(i32(again.record(3), REC["special_words"] + 4 * 5) & 0x400, 0x400)  # 逆刃: other word, bit 10

    def test_learned_skill_bit_rejects_unknown_ids(self) -> None:
        with self.assertRaises(ValueError):
            learned_skill_bit("magic:magicLIGHT:magicCode01")

    def test_preset_summary_names_the_entry_level(self) -> None:
        task = save_module.PresetTask("level53_pre_battle")
        rendered = task.render(save_module.Context())
        summary = task.summary(rendered, "check")
        self.assertIn("entry_level=58", summary)
        self.assertIn("slots=0 ", summary)


if __name__ == "__main__":
    unittest.main()
