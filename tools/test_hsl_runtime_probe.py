import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools import hsl_runtime_probe


class RuntimeProbeTests(unittest.TestCase):
    def test_build_trace_is_read_only_skeleton_with_not_attempted_targets(self):
        with tempfile.TemporaryDirectory() as tmp:
            exe = Path(tmp) / "hsl01.exe"
            exe.write_bytes(b"fake exe")

            with mock.patch.object(hsl_runtime_probe, "find_hsl_pids", return_value=[1234]), \
                 mock.patch.object(hsl_runtime_probe, "find_window", return_value={"window_id": 77}), \
                 mock.patch.object(hsl_runtime_probe, "run_text", return_value="wine-11.0"):
                trace = hsl_runtime_probe.build_trace(exe, Path("tools/hsl_window"))

        self.assertEqual(trace["process"]["pid"], 1234)
        self.assertEqual(trace["process"]["window_id"], 77)
        self.assertTrue(all(target["read_only"] for target in trace["probe_targets"]))
        self.assertTrue(all(target["read_status"] == "not_attempted" for target in trace["probe_targets"]))
        self.assertEqual(trace["samples"][0]["input"]["read_status"], "not_attempted")
        self.assertIn("no runtime memory was read", trace["samples"][0]["evidence_notes"][0])

    def test_write_trace_writes_json_without_raw_memory_or_screenshots(self):
        with mock.patch.object(hsl_runtime_probe, "find_hsl_pids", return_value=[]), \
             mock.patch.object(hsl_runtime_probe, "run_text", return_value="wine-11.0"):
            trace = hsl_runtime_probe.build_trace(Path("/missing/hsl01.exe"), Path("missing-window"), include_window=False)
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "trace.json"

            hsl_runtime_probe.write_trace(trace, output)

            saved = json.loads(output.read_text(encoding="utf-8"))
        self.assertEqual(saved["process"]["exe_exists"], False)
        text = json.dumps(saved)
        self.assertNotIn("memory_dump", text)
        self.assertNotIn("screenshot_path", text)
        self.assertNotIn("capture_path", text)

    def test_vmmap_summary_resolves_known_static_addresses_without_bytes(self):
        vmmap_text = """
WINE_RESERVE                   400000-475000       [  468K     4K     0K     4K] r-x/rwx SM=COW          /Applications/Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-unix/wine
WINE_RESERVE                   475000-480000       [   44K     0K     0K     0K] ---/rwx SM=NUL          /Applications/Wine Stable.app/Contents/Resources/wine/lib/wine/x86_64-unix/wine
"""
        with mock.patch.object(hsl_runtime_probe, "run_text", return_value=vmmap_text):
            summary = hsl_runtime_probe.vmmap_summary(1234)

        self.assertEqual(summary["status"], "ok")
        self.assertEqual(summary["wine_region_count"], 2)
        input_target = next(item for item in summary["known_address_resolution"] if item["name"] == "input_globals")
        self.assertTrue(input_target["mapped"])
        self.assertEqual(input_target["read_status"], "mapped_not_read")
        self.assertNotIn("raw_bytes", json.dumps(summary))
        self.assertNotIn("memory_bytes", json.dumps(summary))

    def test_read_u32_attempt_records_scalar_status_without_dumping_memory(self):
        specs = hsl_runtime_probe.parse_read_u32_specs(
            ["input_current_bits=0x4c6390", "menu_state=0x4c1ac8"]
        )
        with mock.patch.object(
            hsl_runtime_probe,
            "run_lldb_read",
            side_effect=[
                {"tool": "lldb", "status": "ok", "value_u32_hex": "0x00000004"},
                {"tool": "lldb", "status": "ok", "value_u32_hex": "0x00000002"},
            ],
        ):
            attempts = hsl_runtime_probe.read_u32_attempts(1234, specs, timeout=1)

        self.assertEqual(attempts[0]["name"], "input_current_bits")
        self.assertEqual(attempts[0]["value_u32_hex"], "0x00000004")
        self.assertEqual(attempts[1]["name"], "menu_state")
        self.assertEqual(attempts[1]["value_u32_hex"], "0x00000002")
        self.assertTrue(attempts[0]["read_only"])
        self.assertNotIn("memory_bytes", json.dumps(attempts))

    def test_default_scalar_specs_include_input_logical_and_menu_targets(self):
        specs = hsl_runtime_probe.default_scalar_specs()
        by_name = {spec["name"]: spec["address"] for spec in specs}

        self.assertEqual(by_name["input_current_bits"], "0x4c6390")
        self.assertEqual(by_name["input_edge_or_mouse_bits"], "0x4c6398")
        self.assertEqual(by_name["input_prev_bits"], "0x4c1a88")
        self.assertEqual(by_name["logical_x"], "0x4c1a8c")
        self.assertEqual(by_name["logical_y"], "0x4c1a90")
        self.assertEqual(by_name["menu_state"], "0x4c1ac8")
        self.assertEqual(by_name["menu_loop_a"], "0x4c1b98")
        self.assertEqual(by_name["menu_loop_b"], "0x4c1b9c")
        self.assertEqual(by_name["menu_ptr_or_state"], "0x4c1bb8")

    def test_phase_profile_specs_include_camera_and_script_targets_when_needed(self):
        camera = {spec["name"]: spec["address"] for spec in hsl_runtime_probe.phase_profile_specs("camera_scroll")}
        script = {spec["name"]: spec["address"] for spec in hsl_runtime_probe.phase_profile_specs("script_phase")}

        self.assertEqual(camera["camera_or_scroll_x"], "0x4c091c")
        self.assertEqual(camera["camera_or_scroll_y"], "0x4c0920")
        self.assertEqual(script["script_or_phase_state"], "0x4c1d38")
        self.assertEqual(script["handler_table_a_head"], "0x453708")
        self.assertEqual(script["handler_table_b_head"], "0x4537f4")

    def test_read_u32_attempt_dispatches_to_win32_rpm_backend(self):
        specs = hsl_runtime_probe.parse_read_u32_specs(["input_current_bits=0x4c6390"])
        with mock.patch.object(
            hsl_runtime_probe,
            "run_win32_rpm_reads",
            return_value=[{"tool": "win32-rpm", "status": "ok", "value_u32_hex": "0x00000008"}],
        ) as read:
            attempts = hsl_runtime_probe.read_u32_attempts(
                1234,
                specs,
                timeout=1,
                backend="win32-rpm",
                win32_helper=Path("ignored/runtime-probes/bin/hsl_win32_memread.exe"),
            )

        read.assert_called_once()
        self.assertEqual(attempts[0]["tool"], "win32-rpm")
        self.assertEqual(attempts[0]["status"], "ok")
        self.assertEqual(attempts[0]["value_u32_hex"], "0x00000008")
        self.assertNotIn("raw_bytes", json.dumps(attempts))

    def test_parse_win32_rpm_json_extracts_named_scalar_value(self):
        result = hsl_runtime_probe.parse_win32_rpm_json(
            json.dumps(
                {
                    "tool": "win32-rpm",
                    "status": "ok",
                    "reads": [
                        {
                            "name": "input_current_bits",
                            "address": "0x4c6390",
                            "size": "u32",
                            "status": "ok",
                            "value_u32_hex": "0x00000010",
                        }
                    ],
                }
            ),
            "input_current_bits",
        )

        self.assertEqual(result["tool"], "win32-rpm")
        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["value_u32_hex"], "0x00000010")
        self.assertNotIn("memory_bytes", json.dumps(result))

    def test_parse_win32_rpm_json_reports_read_error_code(self):
        result = hsl_runtime_probe.parse_win32_rpm_json(
            json.dumps(
                {
                    "tool": "win32-rpm",
                    "status": "ok",
                    "reads": [
                        {
                            "name": "input_current_bits",
                            "status": "read_failed",
                            "error_code": 299,
                            "bytes_read": 0,
                        }
                    ],
                }
            ),
            "input_current_bits",
        )

        self.assertEqual(result["tool"], "win32-rpm")
        self.assertEqual(result["status"], "read_failed")
        self.assertEqual(result["error_code"], 299)

    def test_parse_win32_rpm_json_reads_extracts_multiple_named_scalars(self):
        payload = json.dumps(
            {
                "tool": "win32-rpm",
                "status": "ok",
                "reads": [
                    {
                        "name": "input_current_bits",
                        "address": "0x4c6390",
                        "size": "u32",
                        "status": "ok",
                        "value_u32_hex": "0x00000000",
                    },
                    {
                        "name": "menu_state",
                        "address": "0x4c1ac8",
                        "size": "u32",
                        "status": "ok",
                        "value_u32_hex": "0x00000002",
                    },
                ],
            }
        )

        result = hsl_runtime_probe.parse_win32_rpm_json_reads(
            payload,
            ["input_current_bits", "menu_state"],
        )

        self.assertEqual(result["input_current_bits"]["value_u32_hex"], "0x00000000")
        self.assertEqual(result["menu_state"]["value_u32_hex"], "0x00000002")

    def test_sample_u32_reads_records_scalar_samples_without_raw_memory(self):
        specs = hsl_runtime_probe.parse_read_u32_specs(["input_current_bits=0x4c6390"])
        values = iter(["0x00000000", "0x00000004", "0x00000000"])

        def fake_attempts(
            pid,
            read_specs,
            timeout,
            backend="lldb",
            win32_helper=None,
            wineprefix=None,
            wine_bin=None,
        ):
            return [
                {
                    "name": read_specs[0]["name"],
                    "address": read_specs[0]["address"],
                    "address_space": "pe_va_candidate",
                    "read_only": True,
                    "size": "u32",
                    "tool": backend,
                    "status": "ok",
                    "value_u32_hex": next(values),
                }
            ]

        with mock.patch.object(hsl_runtime_probe, "read_u32_attempts", side_effect=fake_attempts), \
             mock.patch.object(hsl_runtime_probe.time, "sleep"):
            samples = hsl_runtime_probe.sample_u32_reads(
                280,
                specs,
                timeout=1,
                backend="win32-rpm",
                sample_count=3,
                sample_interval_ms=1,
                phase_hint="player_control",
            )

        self.assertEqual(len(samples), 3)
        self.assertTrue(samples[0]["t_ms"] <= samples[1]["t_ms"] <= samples[2]["t_ms"])
        self.assertEqual(samples[1]["input"]["current_bits"], "0x00000004")
        self.assertEqual(samples[1]["input"]["read_status"], "ok")
        self.assertEqual(samples[1]["input"]["source_read"], "input_current_bits")
        self.assertEqual(samples[1]["scalar_reads"][0]["tool"], "win32-rpm")
        text = json.dumps(samples)
        self.assertNotIn("raw_bytes", text)
        self.assertNotIn("memory_dump", text)
        self.assertNotIn("screenshot_path", text)
        self.assertNotIn("capture_path", text)

    def test_build_trace_can_replace_skeleton_sample_with_scalar_sampling(self):
        specs = hsl_runtime_probe.parse_read_u32_specs(["input_current_bits=0x4c6390"])
        with mock.patch.object(hsl_runtime_probe, "find_hsl_pids", return_value=[4565]), \
             mock.patch.object(hsl_runtime_probe, "find_wine_task_pid", return_value=280), \
             mock.patch.object(hsl_runtime_probe, "run_text", return_value="wine-11.0"), \
             mock.patch.object(
                 hsl_runtime_probe,
                 "read_u32_attempts",
                 return_value=[
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
             ), \
             mock.patch.object(hsl_runtime_probe.time, "sleep"):
            trace = hsl_runtime_probe.build_trace(
                Path("/tmp/hsl01.exe"),
                Path("missing-window"),
                include_window=False,
                read_u32_specs=specs,
                read_backend="win32-rpm",
                sample_count=2,
                sample_interval_ms=1,
                phase_hint="unknown",
                phase_confidence="manual_hint_only",
                phase_profile="player_control",
                interaction_event="manual_phase_mark",
                run_id="session-001",
                operator_note="human observed no input during sampling",
            )

        self.assertEqual(trace["sampling"]["count"], 2)
        self.assertEqual(trace["sampling"]["phase_confidence"], "manual_hint_only")
        self.assertEqual(trace["sampling"]["phase_profile"], "player_control")
        self.assertEqual(trace["sampling"]["interaction_event"]["name"], "manual_phase_mark")
        self.assertEqual(trace["sampling"]["run_id"], "session-001")
        self.assertEqual(trace["sampling"]["operator_note"], "human observed no input during sampling")
        self.assertEqual(trace["sampling"]["read_u32"][0]["name"], "input_current_bits")
        self.assertEqual(len(trace["samples"]), 2)
        self.assertEqual(trace["samples"][0]["input"]["current_bits"], "0x00000000")
        self.assertEqual(trace["samples"][0]["interaction_event"], "manual_phase_mark")

    def test_build_trace_samples_once_when_sample_count_is_one(self):
        specs = hsl_runtime_probe.parse_read_u32_specs(["input_current_bits=0x4c6390"])
        with mock.patch.object(hsl_runtime_probe, "find_hsl_pids", return_value=[4565]), \
             mock.patch.object(hsl_runtime_probe, "find_wine_task_pid", return_value=280), \
             mock.patch.object(hsl_runtime_probe, "run_text", return_value="wine-11.0"), \
             mock.patch.object(
                 hsl_runtime_probe,
                 "read_u32_attempts",
                 return_value=[
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
             ):
            trace = hsl_runtime_probe.build_trace(
                Path("/tmp/hsl01.exe"),
                Path("missing-window"),
                include_window=False,
                read_u32_specs=specs,
                read_backend="win32-rpm",
                sample_count=1,
            )

        self.assertEqual(len(trace["samples"]), 1)
        self.assertEqual(trace["samples"][0]["scalar_reads"][0]["name"], "input_current_bits")


if __name__ == "__main__":
    unittest.main()
