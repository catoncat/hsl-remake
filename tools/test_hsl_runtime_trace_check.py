import json
import tempfile
import unittest
from pathlib import Path

from tools import hsl_runtime_trace_check


def valid_trace(sample_count: int = 2, phase_hint: str = "baseline_unknown_idle") -> dict:
    read_specs = [
        {
            "name": "input_current_bits",
            "address": "0x4c6390",
            "address_space": "pe_va_candidate",
            "size": "u32",
        }
    ]
    return {
        "schema": "hsl_runtime_probe_trace.v1",
        "sampling": {
            "backend": "win32-rpm",
            "phase_hint": phase_hint,
            "phase_profile": "",
            "phase_confidence": "manual_hint_only",
            "interaction_event": {
                "name": "none",
                "source": "operator label only; not proof of original semantics",
            },
            "run_id": "run-001",
            "operator_note": "human observed idle phase; no input",
            "count": sample_count,
            "read_u32": read_specs,
        },
        "samples": [
            {
                "t_ms": index * 250,
                "phase_hint": phase_hint,
                "interaction_event": "none",
                "scalar_reads": [
                    {
                        "name": "input_current_bits",
                        "address": "0x4c6390",
                        "address_space": "pe_va_candidate",
                        "read_only": True,
                        "size": "u32",
                        "tool": "win32-rpm",
                        "status": "ok",
                        "value_u32_hex": "0x00000000",
                    }
                ],
            }
            for index in range(sample_count)
        ],
    }


class RuntimeTraceCheckTests(unittest.TestCase):
    def write_trace(self, trace: dict) -> Path:
        self.tmp = tempfile.TemporaryDirectory()
        path = Path(self.tmp.name) / "trace.json"
        path.write_text(json.dumps(trace), encoding="utf-8")
        return path

    def tearDown(self):
        tmp = getattr(self, "tmp", None)
        if tmp is not None:
            tmp.cleanup()

    def test_valid_scalar_sampling_trace_passes(self):
        errors = hsl_runtime_trace_check.check_trace(
            self.write_trace(valid_trace(sample_count=3)),
            expect_phase="baseline_unknown_idle",
            min_samples=3,
            expect_run_id="run-001",
            expect_phase_confidence="manual_hint_only",
        )

        self.assertEqual(errors, [])

    def test_declared_scalar_missing_from_sample_fails(self):
        trace = valid_trace(sample_count=1)
        trace["sampling"]["read_u32"].append(
            {
                "name": "menu_state",
                "address": "0x4c1ac8",
                "address_space": "pe_va_candidate",
                "size": "u32",
            }
        )

        errors = hsl_runtime_trace_check.check_trace(self.write_trace(trace), min_samples=1)

        self.assertTrue(any("menu_state" in error for error in errors), errors)

    def test_phase_mismatch_fails(self):
        errors = hsl_runtime_trace_check.check_trace(
            self.write_trace(valid_trace(phase_hint="player_control")),
            expect_phase="baseline_unknown_idle",
        )

        self.assertTrue(any("phase_hint" in error for error in errors), errors)

    def test_forbidden_field_fails(self):
        trace = valid_trace()
        trace["samples"][0]["scalar_reads"][0]["raw_bytes"] = "00"

        errors = hsl_runtime_trace_check.check_trace(self.write_trace(trace))

        self.assertTrue(any("raw_bytes" in error for error in errors), errors)

    def test_too_few_samples_fails(self):
        errors = hsl_runtime_trace_check.check_trace(
            self.write_trace(valid_trace(sample_count=1)),
            min_samples=2,
        )

        self.assertTrue(any("sample" in error for error in errors), errors)

    def test_invalid_phase_confidence_fails(self):
        trace = valid_trace()
        trace["sampling"]["phase_confidence"] = "confirmed_menu_semantics"

        errors = hsl_runtime_trace_check.check_trace(self.write_trace(trace))

        self.assertTrue(any("phase_confidence" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
