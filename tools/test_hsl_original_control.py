import tempfile
import unittest
from pathlib import Path

from PIL import Image

from hsl_original_control import check_identity, command_for, scan_captures, wait_for_capture


class OriginalControlTests(unittest.TestCase):
    def test_valid_commands(self):
        self.assertEqual(command_for("click", ["367", "175"], 160), ["click", "367", "175", "160"])
        self.assertEqual(command_for("move", ["0", "479"], 160), ["move", "0", "479"])
        self.assertEqual(command_for("screenshot", [], 160), ["inspect"])
        self.assertEqual(command_for("key", ["space"], 200), ["key", "space", "200"])
        self.assertEqual(command_for("place", ["100", "60"], 160), ["place", "100", "60"])

    def test_invalid_commands_fail_before_input(self):
        for action, operands, hold in [("click", ["640", "0"], 160), ("rclick", ["0", "-1"], 160),
                                       ("key", ["arbitrary"], 160), ("inspect", ["extra"], 160),
                                       ("click", ["x", "1"], 160), ("key", ["space"], 1001),
                                       ("place", ["4000", "0"], 160), ("place", ["100"], 160)]:
            with self.subTest(action=action, operands=operands, hold=hold), self.assertRaises(ValueError):
                command_for(action, operands, hold)

    def test_identity_must_not_change(self):
        check_identity({"pid": 1, "hwnd": "a"}, {"pid": 1, "hwnd": "a"})
        for receipt in ({"pid": 2, "hwnd": "a"}, {"pid": 1, "hwnd": "b"}, {}):
            with self.assertRaises(RuntimeError):
                check_identity({"pid": 1, "hwnd": "a"}, receipt)

    def test_stale_png_not_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            Image.new("RGB", (640, 480)).save(directory / "old.png")
            with self.assertRaises(TimeoutError):
                wait_for_capture(directory, scan_captures(directory), timeout=0)

    def test_fresh_png_is_accepted_but_not_claimed_as_behavior_success(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            before = scan_captures(directory)
            path = directory / "new.png"
            Image.new("RGB", (640, 480)).save(path)
            self.assertEqual(wait_for_capture(directory, before, timeout=0), path)

    def test_ambiguous_or_wrong_size_png_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            Image.new("RGB", (320, 240)).save(directory / "one.png")
            with self.assertRaises(RuntimeError):
                wait_for_capture(directory, {}, timeout=0)
            Image.new("RGB", (640, 480)).save(directory / "two.png")
            with self.assertRaises(RuntimeError):
                wait_for_capture(directory, {}, timeout=0)


if __name__ == "__main__":
    unittest.main()
