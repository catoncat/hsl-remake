#!/usr/bin/env python3
"""Write read-only HSL runtime probe traces.

The collector attaches only through metadata queries and scalar read backends.
It does not patch, control, or dump the original process.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_EXE, WINE_PREFIX

DEFAULT_WINEPREFIX = WINE_PREFIX
DEFAULT_EXE = ORIGINAL_EXE
DEFAULT_WINE_BIN = Path(os.environ.get("WINE_BIN", "/opt/homebrew/bin/wine"))
DEFAULT_OUTPUT = Path("ignored/runtime-probes/latest/trace.json")
DEFAULT_WINDOW_FINDER = Path("tools/hsl_window")
DEFAULT_WIN32_HELPER = Path("ignored/bin/hsl_win32_memread.exe")
TOOL_VERSION = "hsl_runtime_probe.py/0.1"
DEFAULT_PHASE_CONFIDENCE = "manual_hint_only"
READ_NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
VM_REGION_RE = re.compile(
    r"^WINE_RESERVE\s+([0-9a-fA-F]+)-([0-9a-fA-F]+)\s+\[.*?\]\s+(\S+)\s+.*$"
)

SCALAR_TARGETS = [
    {"name": "input_current_bits", "address": "0x4c6390", "group": "input"},
    {"name": "input_edge_or_mouse_bits", "address": "0x4c6398", "group": "input"},
    {"name": "input_prev_bits", "address": "0x4c1a88", "group": "input"},
    {"name": "logical_x", "address": "0x4c1a8c", "group": "logical_cursor"},
    {"name": "logical_y", "address": "0x4c1a90", "group": "logical_cursor"},
    {"name": "menu_state", "address": "0x4c1ac8", "group": "menu"},
    {"name": "menu_loop_a", "address": "0x4c1b98", "group": "menu"},
    {"name": "menu_loop_b", "address": "0x4c1b9c", "group": "menu"},
    {"name": "menu_ptr_or_state", "address": "0x4c1bb8", "group": "menu"},
    {"name": "camera_or_scroll_x", "address": "0x4c091c", "group": "camera"},
    {"name": "camera_or_scroll_y", "address": "0x4c0920", "group": "camera"},
    {"name": "script_or_phase_state", "address": "0x4c1d38", "group": "script_phase"},
    {"name": "handler_table_a_head", "address": "0x453708", "group": "static_dispatch"},
    {"name": "handler_table_b_head", "address": "0x4537f4", "group": "static_dispatch"},
]
SCALAR_TARGETS_BY_NAME = {target["name"]: target for target in SCALAR_TARGETS}
DEFAULT_SCALAR_TARGET_NAMES = [
    "input_current_bits",
    "input_edge_or_mouse_bits",
    "input_prev_bits",
    "logical_x",
    "logical_y",
    "menu_state",
    "menu_loop_a",
    "menu_loop_b",
    "menu_ptr_or_state",
]
PHASE_PROFILES = {
    "title_idle": DEFAULT_SCALAR_TARGET_NAMES,
    "dialogue": DEFAULT_SCALAR_TARGET_NAMES,
    "player_control": DEFAULT_SCALAR_TARGET_NAMES + ["camera_or_scroll_x", "camera_or_scroll_y"],
    "action_menu": DEFAULT_SCALAR_TARGET_NAMES + ["camera_or_scroll_x", "camera_or_scroll_y"],
    "confirm_down": DEFAULT_SCALAR_TARGET_NAMES,
    "confirm_up": DEFAULT_SCALAR_TARGET_NAMES,
    "cancel_down": DEFAULT_SCALAR_TARGET_NAMES,
    "cancel_up": DEFAULT_SCALAR_TARGET_NAMES,
    "click_down": DEFAULT_SCALAR_TARGET_NAMES,
    "click_up": DEFAULT_SCALAR_TARGET_NAMES,
    "camera_scroll": DEFAULT_SCALAR_TARGET_NAMES + ["camera_or_scroll_x", "camera_or_scroll_y"],
    "script_phase": DEFAULT_SCALAR_TARGET_NAMES + ["script_or_phase_state", "handler_table_a_head", "handler_table_b_head"],
}
ACCEPTED_INTERACTION_EVENTS = {
    "none",
    "confirm_down",
    "confirm_up",
    "cancel_down",
    "cancel_up",
    "click_down",
    "click_up",
    "manual_phase_mark",
}


PROBE_TARGETS = [
    {
        "name": "input_globals",
        "source": "static function window 0x415910; runtime global addresses unresolved",
        "address": "0x415910",
        "address_space": "pe_va_candidate",
        "confidence": "static-backed",
        "read_only": True,
        "read_status": "not_attempted",
    },
    {
        "name": "menu_state",
        "source": "static function window 0x42d7c0; state storage unresolved",
        "address": "0x42d7c0",
        "address_space": "pe_va_candidate",
        "confidence": "static-backed",
        "read_only": True,
        "read_status": "not_attempted",
    },
    {
        "name": "logical_ui_hit_test",
        "source": "static function window 0x445977..0x445d25",
        "address": "0x445977",
        "address_space": "pe_va_candidate",
        "confidence": "static-backed",
        "read_only": True,
        "read_status": "not_attempted",
    },
    {
        "name": "script_interpreter",
        "source": "static function window 0x450840; opcode table unresolved",
        "address": "0x450840",
        "address_space": "pe_va_candidate",
        "confidence": "static-backed",
        "read_only": True,
        "read_status": "not_attempted",
    },
    {
        "name": "cursor_camera",
        "source": "runtime probe target planned; address unresolved",
        "address": None,
        "address_space": "unknown",
        "confidence": "provisional",
        "read_only": True,
        "read_status": "not_attempted",
    },
    {
        "name": "selected_unit_action",
        "source": "runtime probe target planned; address unresolved",
        "address": None,
        "address_space": "unknown",
        "confidence": "provisional",
        "read_only": True,
        "read_status": "not_attempted",
    },
]


def sha256_file(path: Path) -> str | None:
    if not path.exists():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_text(command: list[str], timeout: int = 5) -> str | None:
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def run_wine_text(command: list[str], wineprefix: Path, timeout: int = 5) -> str | None:
    env = os.environ.copy()
    env["WINEPREFIX"] = wineprefix.as_posix()
    env.setdefault("WINEDEBUG", "-all")
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=timeout,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def find_wine_task_pid(
    image_name: str,
    wineprefix: Path,
    wine_bin: Path = DEFAULT_WINE_BIN,
) -> int | None:
    output = run_wine_text([wine_bin.as_posix(), "tasklist"], wineprefix, timeout=8)
    if not output:
        return None
    pattern = re.compile(rf"^{re.escape(image_name)}\s+(\d+)\s+", re.IGNORECASE)
    for line in output.splitlines():
        match = pattern.match(line.strip())
        if match:
            return int(match.group(1))
    return None


def run_lldb_read(pid: int, address: str, timeout: int) -> dict[str, Any]:
    command = [
        "lldb",
        "-p",
        str(pid),
        "-b",
        "-o",
        f"memory read --format x --size 4 --count 1 {address}",
        "-o",
        "detach",
        "-o",
        "quit",
    ]
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "tool": "lldb",
            "status": "timeout",
            "stdout_tail": (exc.stdout or "")[-400:] if isinstance(exc.stdout, str) else "",
            "stderr_tail": (exc.stderr or "")[-400:] if isinstance(exc.stderr, str) else "",
        }
    except OSError as exc:
        return {
            "tool": "lldb",
            "status": "unavailable",
            "error": str(exc),
        }

    value = None
    for match in re.finditer(r"\b0x[0-9a-fA-F]{8}\b", completed.stdout):
        value = match.group(0)
    return {
        "tool": "lldb",
        "status": "ok" if completed.returncode == 0 and value is not None else "failed",
        "returncode": completed.returncode,
        "value_u32_hex": value,
        "stdout_tail": completed.stdout[-400:],
        "stderr_tail": completed.stderr[-400:],
    }


def parse_win32_rpm_json(text: str, read_name: str) -> dict[str, Any]:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        return {
            "tool": "win32-rpm",
            "status": "invalid_json",
            "error": str(exc),
            "stdout_tail": text[-400:],
        }

    result: dict[str, Any] = {
        "tool": "win32-rpm",
        "status": str(payload.get("status", "missing_status")),
    }
    if "error_code" in payload:
        result["error_code"] = payload["error_code"]
    if "error" in payload:
        result["error"] = payload["error"]

    reads = payload.get("reads")
    if isinstance(reads, list):
        selected = next(
            (item for item in reads if isinstance(item, dict) and item.get("name") == read_name),
            None,
        )
        if selected is None:
            result["status"] = "read_not_reported"
            return result
        result["status"] = str(selected.get("status", result["status"]))
        if "value_u32_hex" in selected:
            result["value_u32_hex"] = selected["value_u32_hex"]
        if "error_code" in selected:
            result["error_code"] = selected["error_code"]
        if "bytes_read" in selected:
            result["bytes_read"] = selected["bytes_read"]
    return result


def parse_win32_rpm_json_reads(text: str, expected_names: list[str]) -> dict[str, dict[str, Any]]:
    parsed_by_name: dict[str, dict[str, Any]] = {}
    for name in expected_names:
        parsed_by_name[name] = parse_win32_rpm_json(text, name)
    return parsed_by_name


def run_win32_rpm_read(
    pid: int,
    name: str,
    address: str,
    timeout: int,
    helper: Path = DEFAULT_WIN32_HELPER,
    wineprefix: Path = DEFAULT_WINEPREFIX,
    wine_bin: Path = DEFAULT_WINE_BIN,
) -> dict[str, Any]:
    if not helper.exists():
        return {
            "tool": "win32-rpm",
            "status": "unavailable",
            "error": f"helper not found: {helper.as_posix()}",
        }
    command = [
        wine_bin.as_posix(),
        helper.as_posix(),
        "--pid",
        str(pid),
        "--read-u32",
        f"{name}={address}",
    ]
    env = os.environ.copy()
    env["WINEPREFIX"] = wineprefix.as_posix()
    env.setdefault("WINEDEBUG", "-all")
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired as exc:
        return {
            "tool": "win32-rpm",
            "status": "timeout",
            "stdout_tail": (exc.stdout or "")[-400:] if isinstance(exc.stdout, str) else "",
            "stderr_tail": (exc.stderr or "")[-400:] if isinstance(exc.stderr, str) else "",
        }
    except OSError as exc:
        return {
            "tool": "win32-rpm",
            "status": "unavailable",
            "error": str(exc),
        }

    result = parse_win32_rpm_json(completed.stdout.strip(), name)
    result["returncode"] = completed.returncode
    if completed.stderr:
        result["stderr_tail"] = completed.stderr[-400:]
    return result


def run_win32_rpm_reads(
    pid: int,
    specs: list[dict[str, str]],
    timeout: int,
    helper: Path = DEFAULT_WIN32_HELPER,
    wineprefix: Path = DEFAULT_WINEPREFIX,
    wine_bin: Path = DEFAULT_WINE_BIN,
) -> list[dict[str, Any]]:
    if not helper.exists():
        return [
            {
                "tool": "win32-rpm",
                "status": "unavailable",
                "error": f"helper not found: {helper.as_posix()}",
            }
            for _spec in specs
        ]
    command = [
        wine_bin.as_posix(),
        helper.as_posix(),
        "--pid",
        str(pid),
    ]
    for spec in specs:
        command.extend(["--read-u32", f"{spec['name']}={spec['address']}"])
    env = os.environ.copy()
    env["WINEPREFIX"] = wineprefix.as_posix()
    env.setdefault("WINEDEBUG", "-all")
    try:
        completed = subprocess.run(
            command,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired as exc:
        return [
            {
                "tool": "win32-rpm",
                "status": "timeout",
                "stdout_tail": (exc.stdout or "")[-400:] if isinstance(exc.stdout, str) else "",
                "stderr_tail": (exc.stderr or "")[-400:] if isinstance(exc.stderr, str) else "",
            }
            for _spec in specs
        ]
    except OSError as exc:
        return [
            {
                "tool": "win32-rpm",
                "status": "unavailable",
                "error": str(exc),
            }
            for _spec in specs
        ]

    parsed = parse_win32_rpm_json_reads(completed.stdout.strip(), [spec["name"] for spec in specs])
    attempts: list[dict[str, Any]] = []
    for spec in specs:
        result = parsed[spec["name"]]
        result["returncode"] = completed.returncode
        if completed.stderr:
            result["stderr_tail"] = completed.stderr[-400:]
        attempts.append(result)
    return attempts


def parse_vmmap_regions(text: str) -> list[dict[str, Any]]:
    regions: list[dict[str, Any]] = []
    for line in text.splitlines():
        match = VM_REGION_RE.match(line.strip())
        if not match:
            continue
        start = int(match.group(1), 16)
        end = int(match.group(2), 16)
        protections = match.group(3)
        if end <= start:
            continue
        regions.append(
            {
                "start": start,
                "end": end,
                "start_hex": f"0x{start:x}",
                "end_hex": f"0x{end:x}",
                "size": end - start,
                "protections": protections,
            }
        )
    return regions


def resolve_known_addresses(regions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    resolved: list[dict[str, Any]] = []
    for target in PROBE_TARGETS:
        address = target.get("address")
        if not isinstance(address, str) or not address.startswith("0x"):
            continue
        value = int(address, 16)
        containing = next(
            (region for region in regions if int(region["start"]) <= value < int(region["end"])),
            None,
        )
        resolved.append(
            {
                "name": target["name"],
                "address": address,
                "address_space": target["address_space"],
                "mapped": containing is not None,
                "region": containing,
                "read_status": "mapped_not_read" if containing is not None else "not_mapped",
            }
        )
    return resolved


def vmmap_summary(pid: int | None) -> dict[str, Any]:
    if pid is None:
        return {
            "tool": "vmmap",
            "status": "no_pid",
            "wine_region_count": 0,
            "known_address_resolution": [],
        }
    output = run_text(["vmmap", str(pid)], timeout=10)
    if not output:
        return {
            "tool": "vmmap",
            "status": "unavailable_or_failed",
            "wine_region_count": 0,
            "known_address_resolution": [],
        }
    regions = parse_vmmap_regions(output)
    return {
        "tool": "vmmap",
        "status": "ok",
        "wine_region_count": len(regions),
        "known_address_resolution": resolve_known_addresses(regions),
        "note": "address ranges only; no process memory bytes are exported",
    }


def parse_read_u32_specs(values: list[str]) -> list[dict[str, str]]:
    specs: list[dict[str, str]] = []
    for value in values:
        if "=" not in value:
            raise SystemExit(f"invalid --read-u32 spec, expected name=0xaddr: {value}")
        name, address = value.split("=", 1)
        if not name or not READ_NAME_RE.match(name) or not address.startswith("0x"):
            raise SystemExit(f"invalid --read-u32 spec, expected name=0xaddr: {value}")
        int(address, 16)
        specs.append({"name": name, "address": address})
    return specs


def default_scalar_specs() -> list[dict[str, str]]:
    return phase_profile_specs("title_idle")


def phase_profile_specs(profile: str) -> list[dict[str, str]]:
    names = PHASE_PROFILES.get(profile)
    if names is None:
        raise SystemExit(f"unknown phase profile {profile!r}; expected one of {sorted(PHASE_PROFILES)}")
    return [
        {
            "name": name,
            "address": SCALAR_TARGETS_BY_NAME[name]["address"],
        }
        for name in names
    ]


def read_u32_attempts(
    pid: int | None,
    specs: list[dict[str, str]],
    timeout: int,
    backend: str = "lldb",
    win32_helper: Path = DEFAULT_WIN32_HELPER,
    wineprefix: Path = DEFAULT_WINEPREFIX,
    wine_bin: Path = DEFAULT_WINE_BIN,
) -> list[dict[str, Any]]:
    attempts: list[dict[str, Any]] = []
    win32_results: list[dict[str, Any]] | None = None
    if pid is not None and backend == "win32-rpm":
        win32_results = run_win32_rpm_reads(
            pid,
            specs,
            timeout,
            helper=win32_helper,
            wineprefix=wineprefix,
            wine_bin=wine_bin,
        )
    for spec in specs:
        attempt = {
            "name": spec["name"],
            "address": spec["address"],
            "address_space": "pe_va_candidate",
            "read_only": True,
            "size": "u32",
        }
        if pid is None:
            attempt.update({"status": "no_pid", "tool": backend})
        elif backend == "lldb":
            attempt.update(run_lldb_read(pid, spec["address"], timeout))
        elif backend == "win32-rpm":
            assert win32_results is not None
            attempt.update(win32_results[len(attempts)])
        else:
            attempt.update({"status": "unsupported_backend", "tool": backend})
        attempts.append(attempt)
    return attempts


def sample_u32_reads(
    pid: int | None,
    specs: list[dict[str, str]],
    timeout: int,
    backend: str,
    sample_count: int,
    sample_interval_ms: int,
    phase_hint: str,
    interaction_event: str = "none",
    win32_helper: Path = DEFAULT_WIN32_HELPER,
    wineprefix: Path = DEFAULT_WINEPREFIX,
    wine_bin: Path = DEFAULT_WINE_BIN,
) -> list[dict[str, Any]]:
    samples: list[dict[str, Any]] = []
    start = time.monotonic()
    for index in range(max(sample_count, 1)):
        attempts = read_u32_attempts(
            pid,
            specs,
            timeout,
            backend=backend,
            win32_helper=win32_helper,
            wineprefix=wineprefix,
            wine_bin=wine_bin,
        )
        sample = empty_sample()
        sample["t_ms"] = int((time.monotonic() - start) * 1000)
        sample["phase_hint"] = phase_hint
        sample["interaction_event"] = interaction_event
        sample["scalar_reads"] = attempts
        sample["evidence_notes"] = [
            "read-only scalar sampling only; no raw memory exported",
        ]
        input_attempt = next((item for item in attempts if item.get("name") == "input_current_bits"), None)
        if input_attempt is not None:
            sample["input"]["current_bits"] = input_attempt.get("value_u32_hex")
            sample["input"]["read_status"] = str(input_attempt.get("status", "missing_status"))
            sample["input"]["source_read"] = "input_current_bits"
        samples.append(sample)
        if index < sample_count - 1 and sample_interval_ms > 0:
            time.sleep(float(sample_interval_ms) / 1000.0)
    return samples


def find_hsl_pids() -> list[int]:
    output = run_text(["ps", "-axo", "pid=,args="])
    if not output:
        return []
    pids: list[int] = []
    for line in output.splitlines():
        if "hsl01.exe" not in line.lower():
            continue
        if "tools/hsl_runtime_probe.py" in line or "pgrep" in line or "/bin/zsh" in line:
            continue
        parts = line.strip().split(maxsplit=1)
        if len(parts) != 2:
            continue
        args = parts[1].lower()
        if "c:\\hsl\\hsl01.exe" not in args and "c:/hsl/hsl01.exe" not in args:
            continue
        try:
            pids.append(int(parts[0]))
        except ValueError:
            continue
    return pids


def find_window(window_finder: Path) -> dict[str, Any] | None:
    if not window_finder.exists() or not window_finder.is_file():
        return None
    output = run_text([window_finder.as_posix()])
    if not output:
        return None
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return {"raw": output}


def empty_sample() -> dict[str, Any]:
    return {
        "t_ms": 0,
        "phase_hint": "unknown",
        "input": {
            "current_bits": None,
            "pressed_edge_bits": None,
            "mouse_client": None,
            "read_status": "not_attempted",
        },
        "cursor_camera": {
            "cursor": None,
            "camera": None,
            "coordinate_space": "unknown",
            "read_status": "not_attempted",
        },
        "menu": {
            "visible": None,
            "selected_index": None,
            "hit_object": None,
            "command_candidate": None,
            "read_status": "not_attempted",
        },
        "battle": {
            "selected_unit": None,
            "selected_action": None,
            "turn_owner": None,
            "round_counter": None,
            "read_status": "not_attempted",
        },
        "script": {
            "status_id": None,
            "opcode_candidate": None,
            "program_counter": None,
            "read_status": "not_attempted",
        },
        "evidence_notes": [
            "first-stage skeleton only; no runtime memory was read",
        ],
    }


def build_trace(
    exe: Path,
    window_finder: Path,
    include_window: bool = True,
    resolve_addresses: bool = False,
    read_u32_specs: list[dict[str, str]] | None = None,
    read_backend: str = "lldb",
    read_timeout: int = 8,
    win32_helper: Path = DEFAULT_WIN32_HELPER,
    wineprefix: Path = DEFAULT_WINEPREFIX,
    wine_bin: Path = DEFAULT_WINE_BIN,
    sample_count: int = 1,
    sample_interval_ms: int = 250,
    phase_hint: str = "unknown",
    phase_confidence: str = DEFAULT_PHASE_CONFIDENCE,
    run_id: str = "",
    operator_note: str = "",
    phase_profile: str = "",
    interaction_event: str = "none",
) -> dict[str, Any]:
    created_at = datetime.now(timezone.utc).isoformat()
    pids = find_hsl_pids()
    window = find_window(window_finder) if include_window else None
    pid = pids[0] if pids else None
    win32_pid = (
        find_wine_task_pid("hsl01.exe", wineprefix, wine_bin)
        if read_backend == "win32-rpm"
        else None
    )
    trace = {
        "schema": "hsl_runtime_probe_trace.v1",
        "source_policy": "runtime traces stay ignored/private; traces contain metadata, address-range resolution, and optional scalar read-only values, never raw memory dumps",
        "created_at": created_at,
        "tool": TOOL_VERSION,
        "process": {
            "launch_route": "attach-only",
            "exe_path": exe.as_posix(),
            "exe_exists": exe.exists(),
            "exe_size": exe.stat().st_size if exe.exists() else None,
            "exe_sha256": sha256_file(exe),
            "wineprefix": wineprefix.as_posix(),
            "pid": pid,
            "win32_pid": win32_pid,
            "candidate_pids": pids,
            "wine_bin": wine_bin.as_posix(),
            "wine_version": run_text([wine_bin.as_posix(), "--version"]),
            "window_id": window.get("window_id") if isinstance(window, dict) else None,
            "window": window,
        },
        "probe_targets": PROBE_TARGETS,
        "samples": [empty_sample()],
        "next_probe_route": [
            "resolve static PE addresses to Wine process module addresses",
            "sample input globals around supervised input without writing process memory",
            "expand only after read_status can be upgraded from not_attempted to ok or negative",
        ],
        "forbidden_first_stage": [
            "whole-desktop screenshots",
            "raw memory dumps in tracked paths",
            "writing to the original process",
            "claiming command semantics from capture alone",
        ],
    }
    if resolve_addresses:
        trace["runtime_address_resolution"] = vmmap_summary(pid)
    if read_u32_specs:
        target_names = {spec["name"] for spec in read_u32_specs}
        trace["sampling"] = {
            "backend": read_backend,
            "count": max(sample_count, 1),
            "interval_ms": sample_interval_ms,
            "phase_hint": phase_hint,
            "phase_profile": phase_profile,
            "phase_confidence": phase_confidence,
            "interaction_event": {
                "name": interaction_event,
                "source": "operator label only; not proof of original semantics",
            },
            "run_id": run_id,
            "operator_note": operator_note,
            "read_u32": [
                {
                    "name": spec["name"],
                    "address": spec["address"],
                    "address_space": "pe_va_candidate",
                    "size": "u32",
                    "target_group": SCALAR_TARGETS_BY_NAME.get(spec["name"], {}).get("group", "custom"),
                }
                for spec in read_u32_specs
            ],
            "available_phase_profiles": sorted(PHASE_PROFILES),
            "static_target_note": "0x453708 and 0x4537f4 are static dispatch candidate heads; scalar reads there do not decode handlers or semantics.",
            "source_policy": "read-only scalar sampling; no raw memory bytes are exported",
        }
        trace["read_attempts"] = read_u32_attempts(
            win32_pid if read_backend == "win32-rpm" else pid,
            read_u32_specs,
            read_timeout,
            backend=read_backend,
            win32_helper=win32_helper,
            wineprefix=wineprefix,
            wine_bin=wine_bin,
        )
        trace["samples"] = sample_u32_reads(
            win32_pid if read_backend == "win32-rpm" else pid,
            read_u32_specs,
            read_timeout,
            read_backend,
            sample_count,
            sample_interval_ms,
            phase_hint,
            interaction_event=interaction_event,
            win32_helper=win32_helper,
            wineprefix=wineprefix,
            wine_bin=wine_bin,
        )
        trace["probe_target_groups"] = sorted(
            {SCALAR_TARGETS_BY_NAME.get(name, {}).get("group", "custom") for name in target_names}
        )
    return trace


def write_trace(trace: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(trace, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--window-finder", type=Path, default=DEFAULT_WINDOW_FINDER)
    parser.add_argument("--no-window", action="store_true")
    parser.add_argument("--resolve-addresses", action="store_true")
    parser.add_argument("--read-u32", action="append", default=[], metavar="NAME=0xADDR")
    parser.add_argument(
        "--read-default-scalars",
        action="store_true",
        help="Read the current baseline input/logical/menu scalar target set.",
    )
    parser.add_argument(
        "--phase-profile",
        choices=sorted(PHASE_PROFILES),
        default="",
        help="Read the scalar target set for a supervised runtime phase label.",
    )
    parser.add_argument("--read-backend", choices=["lldb", "win32-rpm"], default="lldb")
    parser.add_argument("--read-timeout", type=int, default=8)
    parser.add_argument("--sample-count", type=int, default=1)
    parser.add_argument("--sample-interval-ms", type=int, default=250)
    parser.add_argument("--phase-hint", default="unknown")
    parser.add_argument("--phase-confidence", default=DEFAULT_PHASE_CONFIDENCE)
    parser.add_argument("--interaction-event", choices=sorted(ACCEPTED_INTERACTION_EVENTS), default="none")
    parser.add_argument("--run-id", default="")
    parser.add_argument("--operator-note", default="")
    parser.add_argument("--win32-helper", type=Path, default=DEFAULT_WIN32_HELPER)
    parser.add_argument("--wineprefix", type=Path, default=DEFAULT_WINEPREFIX)
    parser.add_argument("--wine-bin", type=Path, default=DEFAULT_WINE_BIN)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    start = time.monotonic()
    read_u32_specs = parse_read_u32_specs(args.read_u32)
    if args.phase_profile:
        args.phase_hint = args.phase_profile if args.phase_hint == "unknown" else args.phase_hint
        seen = {spec["name"] for spec in read_u32_specs}
        read_u32_specs.extend(spec for spec in phase_profile_specs(args.phase_profile) if spec["name"] not in seen)
    if args.read_default_scalars:
        seen = {spec["name"] for spec in read_u32_specs}
        read_u32_specs.extend(spec for spec in default_scalar_specs() if spec["name"] not in seen)
    trace = build_trace(
        args.exe,
        args.window_finder,
        include_window=not args.no_window,
        resolve_addresses=args.resolve_addresses,
        read_u32_specs=read_u32_specs,
        read_backend=args.read_backend,
        read_timeout=args.read_timeout,
        win32_helper=args.win32_helper,
        wineprefix=args.wineprefix,
        wine_bin=args.wine_bin,
        sample_count=args.sample_count,
        sample_interval_ms=args.sample_interval_ms,
        phase_hint=args.phase_hint,
        phase_confidence=args.phase_confidence,
        run_id=args.run_id,
        operator_note=args.operator_note,
        phase_profile=args.phase_profile,
        interaction_event=args.interaction_event,
    )
    trace["samples"][0]["t_ms"] = int((time.monotonic() - start) * 1000)
    write_trace(trace, args.output)
    print(f"wrote runtime probe trace: {args.output}")
    print(f"pid: {trace['process']['pid']}, window_id: {trace['process']['window_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
