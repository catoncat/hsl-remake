import json
import unittest

from tools.hsl_native_map_scroll_probe import PACKET, request_delta


class NativeMapScrollTests(unittest.TestCase):
    def test_strict_edge_thresholds(self):
        self.assertEqual(request_delta(9, 240), (-12, 0))
        self.assertEqual(request_delta(10, 240), (0, 0))
        self.assertEqual(request_delta(630, 240), (0, 0))
        self.assertEqual(request_delta(631, 240), (12, 0))
        self.assertEqual(request_delta(320, 10), (0, 0))
        self.assertEqual(request_delta(320, 470), (0, 0))
        self.assertEqual(request_delta(9, 471), (-12, 12))

    def test_direction_flags_and_double_loop(self):
        self.assertEqual(request_delta(320, 240, 1), (-12, 0))
        self.assertEqual(request_delta(320, 240, 15), (0, 0))
        self.assertEqual(request_delta(9, 471, 0x200), (-24, 24))

    def test_all_native_returns_and_accumulator_deltas(self):
        packet = json.loads(PACKET.read_text())
        self.assertTrue(packet["cases"])
        for case in packet["cases"]:
            expected = request_delta(*case["viewport_pointer"], case["input_flags"])
            self.assertEqual(tuple(case["delta"]), expected)
            self.assertEqual([a-b for a,b in zip(case["request_after"],case["request_before"])], list(expected))
            self.assertTrue(case["returned"] and case["camera_origin_unchanged"])


if __name__ == "__main__":
    unittest.main()
