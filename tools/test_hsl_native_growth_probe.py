import json
import unittest

from tools.hsl_native_growth_probe import PACKET, allowance


class NativeGrowthAllowanceTests(unittest.TestCase):
    def test_five_points_are_a_budget_across_four_attributes(self):
        self.assertEqual(allowance([16, 16, 8, 12], [99, 99, 99, 99]), 5)
        self.assertEqual(allowance([16, 16, 8, 12], [17, 17, 9, 12]), 3)
        self.assertEqual(allowance([16, 16, 8, 12], [16, 16, 8, 12]), 0)

    def test_original_sums_before_clamping(self):
        self.assertEqual(allowance([20, 20, 20, 20], [19, 22, 20, 20]), 1)
        self.assertEqual(allowance([20, 20, 20, 20], [19, 19, 19, 19]), 0)

    def test_input_shape_and_bounds(self):
        for base, caps, requested in [([1], [2], 5), ([0]*4, [1]*4, 1.5), ([True]*4, [10]*4, 5),
                                      ([100001]*4, [2]*4, 5)]:
            with self.subTest(base=base), self.assertRaises(ValueError):
                allowance(base, caps, requested)

    def test_all_recorded_original_returns_match_model(self):
        packet = json.loads(PACKET.read_text())
        self.assertEqual(packet["levelup_request"], 5)
        self.assertEqual(packet["attributes"], ["str", "dex", "mind", "con"])
        self.assertTrue(packet["cases"])
        for case in packet["cases"]:
            self.assertTrue(case["returned"] and case["roster_unchanged"])
            self.assertEqual(case["result"], allowance(case["base"], case["caps"], case["effective_request"]))
            if case["entry"] == "0x439f70":
                self.assertEqual(case["effective_request"], 5)


if __name__ == "__main__":
    unittest.main()
