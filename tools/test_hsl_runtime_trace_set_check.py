import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_runtime_trace_set_check
from tools.test_hsl_runtime_trace_check import valid_trace


def trace_with_values(
    phase_hint: str,
    values: list[str],
    run_id: str = "run-001",
    phase_confidence: str = "manual_hint_only",
    phase_profile: str = "",
    interaction_event: str = "none",
) -> dict:
    trace = valid_trace(sample_count=len(values), phase_hint=phase_hint)
    trace["source_policy"] = {"run_id": run_id}
    trace["sampling"]["run_id"] = run_id
    trace["sampling"]["phase_confidence"] = phase_confidence
    trace["sampling"]["phase_profile"] = phase_profile
    trace["sampling"]["interaction_event"]["name"] = interaction_event
    for sample, value in zip(trace["samples"], values):
        sample["phase_hint"] = phase_hint
        sample["interaction_event"] = interaction_event
        sample["scalar_reads"][0]["value_u32_hex"] = value
    return trace


class RuntimeTraceSetCheckTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write_trace(self, name: str, trace: dict) -> Path:
        path = self.root / name
        path.write_text(json.dumps(trace), encoding="utf-8")
        return path

    def test_valid_trace_set_summarizes_compact_scalar_counts(self):
        first = self.write_trace(
            "baseline.json",
            trace_with_values("baseline_unknown_idle", ["0x00000000", "0x00000000"]),
        )
        second = self.write_trace(
            "player.json",
            trace_with_values(
                "player_control",
                ["0x00000000", "0x00000001"],
                phase_confidence="correlated_scalar_change",
                phase_profile="player_control",
                interaction_event="manual_phase_mark",
            ),
        )

        summary, errors = hsl_runtime_trace_set_check.check_trace_set(
            [first, second],
            min_traces=2,
            expect_run_id="run-001",
        )

        self.assertEqual(errors, [])
        self.assertEqual(summary["phases"], ["baseline_unknown_idle", "player_control"])
        self.assertEqual(
            summary["per_phase"]["player_control"]["input_current_bits"]["value_counts"],
            {"0x00000000": 1, "0x00000001": 1},
        )

    def test_run_id_mismatch_fails(self):
        first = self.write_trace("a.json", trace_with_values("baseline_unknown_idle", ["0x0"], "run-001"))
        second = self.write_trace("b.json", trace_with_values("player_control", ["0x1"], "run-002"))

        summary, errors = hsl_runtime_trace_set_check.check_trace_set([first, second])

        self.assertIsNone(summary)
        self.assertTrue(any("run_id mismatch" in error for error in errors), errors)

    def test_forbidden_private_field_fails_via_single_trace_check(self):
        trace = trace_with_values("baseline_unknown_idle", ["0x0"])
        trace["samples"][0]["scalar_reads"][0]["raw_bytes"] = "00"
        path = self.write_trace("trace.json", trace)

        summary, errors = hsl_runtime_trace_set_check.check_trace_set([path])

        self.assertIsNone(summary)
        self.assertTrue(any("raw_bytes" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
