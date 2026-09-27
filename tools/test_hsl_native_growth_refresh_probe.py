import json
import unittest
from pathlib import Path

from tools.hsl_native_growth_refresh_probe import PACKET, swordman_unequipped


class NativeGrowthRefreshProbeTests(unittest.TestCase):
    def setUp(self):
        self.packet = json.loads(Path(PACKET).read_text())

    def test_leonard_caps_are_native_job_table_row(self):
        loader = self.packet["cap_loader"]
        self.assertEqual(loader["index_formula"], "job_code - 80")
        self.assertEqual(loader["rows"][0], [90, 88, 80, 94])
        self.assertEqual(loader["leonard_caps"], {"str": 90, "dex": 88, "mind": 80, "con": 94})

    def test_saved_native_cases_match_independent_swordman_model(self):
        source = self.packet["source_profile"]
        delta = self.packet["initial_equipment_delta"]
        for case in self.packet["cases"]:
            model = swordman_unequipped(source, case["attributes"], case["level"],
                                        case["input_current_hp"], case["input_current_mp"])
            native = case["native_equipped"]
            for key in ("max_hp", "max_mp", "attack", "defense", "speed", "hit_rate", "magic_attack"):
                expected = model[key] + delta[key]
                if key == "max_hp":
                    expected = max(1, expected)
                if key == "max_mp":
                    expected = max(0, expected)
                self.assertEqual(native[key], expected, (case["case"], key))
            self.assertEqual(native["resist_by_type"], {
                key: model["resist_by_type"][key] + delta["resist_by_type"][key]
                for key in model["resist_by_type"]})

    def test_native_refresh_does_not_refill_current_hp(self):
        baseline = next(case for case in self.packet["cases"] if case["case"] == "baseline")
        level_two = next(case for case in self.packet["cases"] if case["case"] == "level_two_no_refill")
        self.assertGreater(level_two["native_equipped"]["max_hp"], baseline["native_equipped"]["max_hp"])
        self.assertEqual(level_two["native_equipped"]["current_hp"], baseline["native_equipped"]["current_hp"])
        clamped = next(case for case in self.packet["cases"] if case["case"] == "at_caps_clamp_current")
        self.assertEqual(clamped["native_equipped"]["current_hp"], clamped["native_equipped"]["max_hp"])
        self.assertEqual(clamped["native_equipped"]["current_mp"], 0)


if __name__ == "__main__":
    unittest.main()
