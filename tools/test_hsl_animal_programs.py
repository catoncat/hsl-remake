import copy
import json
from pathlib import Path
import tempfile
import unittest

from hsltools.assets.animal_programs import ROOT, SOURCES, build, check, compile_sources, definitions, parse_program
from hsltools.native.image import image
from tools.hsl_native_animal_probe import PACKET, validate_observations


class AnimalProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sources = [(ROOT / path).read_bytes() for path in SOURCES.values()]
        cls.packet = build()
        cls.catalog = cls.packet["opcode_definitions"]
        cls.records = {row["code"]: row for row in cls.packet["records"]}

    def test_entire_packet_rebuilds_from_original_sources(self):
        self.assertEqual(check(), self.packet)
        self.assertEqual(len(self.records), 66)
        self.assertEqual(self.packet["summary"]["programs_by_channel"],
                         {"action": 66, "m_action": 18, "s_action": 19})
        self.assertEqual(self.packet["summary"]["instructions"], 663)
        self.assertEqual(sorted(row["value"] for row in self.catalog.values()), list(range(36)))

    def test_special_program_preserves_nonframe_operations_and_offsets(self):
        row = self.records["SID_PLAYER0"]
        self.assertEqual(row["sid"], 0)  # File P001 is not actor slot 1.
        program = row["programs"]["s_action"]
        self.assertEqual([(i["op"], i["opcode"], i["args"]) for i in program], [
            ("aniSetXYDisp", 10, [-640, 0]), ("aniShadowBG", 12, []),
            ("aniMoveToCenter", 13, []), ("aniInsertCastObject", 14, [-160, -150, 2, 6, 6])])
        self.assertEqual([i["source_line"] for i in program], [14, 14, 14, 15])

    def test_flash_position_preserves_order_before_shape(self):
        program = self.records["SID_PLAYER0"]["programs"]["action"]
        flash = next(i for i, op in enumerate(program) if op["op"] == "aniInsertAttackFlash")
        self.assertEqual(program[flash]["args"], [-90, -120])
        self.assertEqual(program[flash - 1]["args"], [3])
        self.assertEqual((program[flash + 1]["op"], program[flash + 1]["args"]), ("aniSetShape", [3]))
        self.assertEqual(program[-1]["op"], "aniDelay")  # No invented terminal in the source IR.

    def test_commented_mage_cast_and_replaced_actions_stay_inactive(self):
        self.assertEqual(set(self.records["SID_ENEMY026"]["programs"]), {"action"})
        self.assertNotIn("m_shape", self.records["SID_ENEMY026"]["fields"])
        player9 = self.records["SID_PLAYER9"]["programs"]["action"]
        flashes = [i["args"] for i in player9 if i["op"] == "aniInsertAttackFlash"]
        self.assertEqual(flashes, [[-300, -60]])
        enemy24 = self.records["SID_ENEMY024"]
        self.assertNotIn("fh_shape", enemy24["fields"])
        self.assertTrue(any(i["op"] == "aniInsertAttackFlash" for i in enemy24["programs"]["action"]))

    def test_repeated_zoom_and_nonmonotonic_frames_are_not_collapsed(self):
        zooms = [i for i in self.records["SID_PLAYER5"]["programs"]["action"] if i["op"] == "aniSetZoom"]
        self.assertEqual([i["args"][0] for i in zooms], list(range(0x11000, 0x17000, 0x1000)))
        self.assertEqual(zooms[0]["arg_tokens"], ["0x00011000"])
        frames = [i["args"][0] for i in self.records["SID_PLAYER7"]["programs"]["action"] if i["op"] == "aniSetShape"]
        self.assertEqual(frames, [1, 0, 1, 0, 1, 2, 3])

    def test_unknown_or_malformed_instructions_fail_instead_of_disappearing(self):
        for text in ("aniGuess,1", "aniDelay", "aniSetShape,aniDelay,3", "aniSetShape,1,99",
                     "aniDelay,1,", "aniSetZoom,0x100000000", "aniDelay,1.5"):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse_program(text, 10, self.catalog)

    def test_duplicate_fields_unknown_fields_and_missing_channels_fail(self):
        original = self.sources[0]
        variants = [original.replace(b"code     = SID_PLAYER0", b"code = SID_PLAYER0\ncode = SID_PLAYER0", 1),
                    original.replace(b"s_number = 7", b"s_unknown = 7", 1),
                    original.replace(b"s_number = 7", b";s_number = 7", 1),
                    original.replace(b"aniSetShape,1", b"aniSetShape,99", 1)]
        for raw in variants:
            with self.subTest(source=raw[:70]), self.assertRaises(ValueError):
                compile_sources(raw, *self.sources[1:])

    def test_packet_tampering_is_detected_without_original_installation(self):
        changed = copy.deepcopy(self.packet)
        changed["records"][0]["programs"]["action"][0]["args"] = [99]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "programs.json"
            path.write_text(json.dumps(changed))
            with self.assertRaises(ValueError):
                check(path)

    def test_native_packet_keeps_delay_setup_and_resume_distinct(self):
        native = json.loads(PACKET.read_text())
        validate_observations(native)
        sample = next(row for row in native["cases"] if row["name"] == "delay_2")
        self.assertEqual([(s["phase"], s["cursor_word"]) for s in sample["states"]],
                         [(0, 0), (1, 2), (1, 2), (0, 2), (0, 4), (101, 5)])
        changed = copy.deepcopy(native)
        changed["cases"][2]["states"][3]["cursor_word"] = 4
        with self.assertRaises(ValueError):
            validate_observations(changed)
        self.assertEqual(native["source_program_sha256"], self.packet["sources"]["programs"]["sha256"])

    def test_native_executable_mismatch_fails_before_parsing_or_execution(self):
        with self.assertRaisesRegex(ValueError, "Unsupported EXE"):
            image(b"not the original executable")


if __name__ == "__main__":
    unittest.main()
