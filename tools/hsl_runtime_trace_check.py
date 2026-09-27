#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


EXPECTED_SCHEMA = "hsl_runtime_probe_trace.v1"
ACCEPTED_READ_STATUSES = {
    "failed",
    "no_pid",
    "ok",
    "read_failed",
    "read_not_reported",
    "timeout",
    "unavailable",
}
ACCEPTED_PHASE_CONFIDENCE = {
    "baseline_unknown",
    "correlated_scalar_change",
    "manual_hint_only",
    "operator_observed",
}
ACCEPTED_PHASE_PROFILES = {
    "",
    "action_menu",
    "camera_scroll",
    "cancel_down",
    "cancel_up",
    "click_down",
    "click_up",
    "confirm_down",
    "confirm_up",
    "dialogue",
    "player_control",
    "script_phase",
    "title_idle",
}
ACCEPTED_INTERACTION_EVENTS = {
    "none",
    "cancel_down",
    "cancel_up",
    "click_down",
    "click_up",
    "confirm_down",
    "confirm_up",
    "manual_phase_mark",
}
FORBIDDEN_TOKENS = {
    "capture_path",
    "memory_dump",
    "raw_bytes",
    "screenshot_path",
}
MAX_PRINTED_ERRORS = 8
MAX_OPERATOR_NOTE_CHARS = 240


def load_json(path: Path) -> tuple[Any | None, str | None]:
    try:
        return json.loads(path.read_text(encoding="utf-8")), None
    except FileNotFoundError:
        return None, f"missing file: {path}"
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}"


def field_path(parent: str, key: str) -> str:
    return f"{parent}.{key}" if parent else key


def collect_forbidden(value: Any, prefix: str = "") -> list[str]:
    errors: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            child_path = field_path(prefix, key_text)
            if key_text in FORBIDDEN_TOKENS:
                errors.append(f"forbidden field {child_path}")
            errors.extend(collect_forbidden(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            errors.extend(collect_forbidden(child, f"{prefix}[{index}]"))
    elif isinstance(value, str):
        for token in sorted(FORBIDDEN_TOKENS):
            if token in value:
                location = prefix or "<root>"
                errors.append(f"forbidden string token {token!r} at {location}")
    return errors


def is_u32_value(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return 0 <= value <= 0xFFFFFFFF
    if isinstance(value, str):
        try:
            parsed = int(value, 16 if value.lower().startswith("0x") else 10)
        except ValueError:
            return False
        return 0 <= parsed <= 0xFFFFFFFF
    return False


def declared_scalar_names(trace: dict[str, Any]) -> list[str]:
    sampling = trace.get("sampling")
    if not isinstance(sampling, dict):
        return []
    read_u32 = sampling.get("read_u32")
    if not isinstance(read_u32, list):
        return []
    names: list[str] = []
    for item in read_u32:
        if isinstance(item, dict) and isinstance(item.get("name"), str):
            names.append(item["name"])
    return names


def check_sampling(
    trace: dict[str, Any],
    expect_phase: str | None,
    expect_run_id: str | None = None,
    expect_phase_confidence: str | None = None,
) -> list[str]:
    errors: list[str] = []
    sampling = trace.get("sampling")
    if not isinstance(sampling, dict):
        return ["sampling must be an object"]

    backend = sampling.get("backend")
    if not isinstance(backend, str) or not backend:
        errors.append("sampling.backend must be a non-empty string")

    phase_hint = sampling.get("phase_hint")
    if not isinstance(phase_hint, str) or not phase_hint:
        errors.append("sampling.phase_hint must be a non-empty string")
    elif expect_phase is not None and phase_hint != expect_phase:
        errors.append(f"sampling.phase_hint mismatch: expected {expect_phase!r}, got {phase_hint!r}")

    phase_confidence = sampling.get("phase_confidence")
    if phase_confidence is not None:
        if phase_confidence not in ACCEPTED_PHASE_CONFIDENCE:
            errors.append(
                "sampling.phase_confidence must be one of "
                f"{sorted(ACCEPTED_PHASE_CONFIDENCE)}, got {phase_confidence!r}"
            )
    if expect_phase_confidence is not None and phase_confidence != expect_phase_confidence:
        errors.append(
            f"sampling.phase_confidence mismatch: expected {expect_phase_confidence!r}, got {phase_confidence!r}"
        )

    phase_profile = sampling.get("phase_profile")
    if phase_profile is not None and phase_profile not in ACCEPTED_PHASE_PROFILES:
        errors.append(
            "sampling.phase_profile must be one of "
            f"{sorted(ACCEPTED_PHASE_PROFILES)}, got {phase_profile!r}"
        )

    interaction_event = sampling.get("interaction_event")
    if interaction_event is not None:
        if not isinstance(interaction_event, dict):
            errors.append("sampling.interaction_event must be an object when present")
        else:
            event_name = interaction_event.get("name")
            if event_name not in ACCEPTED_INTERACTION_EVENTS:
                errors.append(
                    "sampling.interaction_event.name must be one of "
                    f"{sorted(ACCEPTED_INTERACTION_EVENTS)}, got {event_name!r}"
                )
            source = interaction_event.get("source")
            if source is not None and not isinstance(source, str):
                errors.append("sampling.interaction_event.source must be a string when present")

    run_id = sampling.get("run_id")
    if run_id is not None and not isinstance(run_id, str):
        errors.append("sampling.run_id must be a string when present")
    elif expect_run_id is not None and run_id != expect_run_id:
        errors.append(f"sampling.run_id mismatch: expected {expect_run_id!r}, got {run_id!r}")

    operator_note = sampling.get("operator_note")
    if operator_note is not None and not isinstance(operator_note, str):
        errors.append("sampling.operator_note must be a string when present")
    elif isinstance(operator_note, str) and len(operator_note) > MAX_OPERATOR_NOTE_CHARS:
        errors.append(f"sampling.operator_note must be <= {MAX_OPERATOR_NOTE_CHARS} characters")

    read_u32 = sampling.get("read_u32")
    if not isinstance(read_u32, list):
        errors.append("sampling.read_u32 must be a list")
    elif not read_u32:
        errors.append("sampling.read_u32 must include at least one scalar")
    else:
        names: set[str] = set()
        for index, item in enumerate(read_u32):
            prefix = f"sampling.read_u32[{index}]"
            if not isinstance(item, dict):
                errors.append(f"{prefix} must be an object")
                continue
            name = item.get("name")
            if not isinstance(name, str) or not name:
                errors.append(f"{prefix}.name must be a non-empty string")
            elif name in names:
                errors.append(f"{prefix}.name duplicates {name!r}")
            else:
                names.add(name)
            if item.get("size") != "u32":
                errors.append(f"{prefix}.size must be 'u32'")
            target_group = item.get("target_group")
            if target_group is not None and not isinstance(target_group, str):
                errors.append(f"{prefix}.target_group must be a string when present")
            address = item.get("address")
            if not isinstance(address, str) or not address.startswith("0x") or not is_u32_value(address):
                errors.append(f"{prefix}.address must be a u32 hex address")
    return errors


def check_scalar_read(
    sample: dict[str, Any],
    sample_index: int,
    required_names: list[str],
) -> list[str]:
    scalar_reads = sample.get("scalar_reads")
    if not isinstance(scalar_reads, list):
        return [f"samples[{sample_index}].scalar_reads must be a list"]

    errors: list[str] = []
    names_seen: set[str] = set()
    for read_index, read in enumerate(scalar_reads):
        prefix = f"samples[{sample_index}].scalar_reads[{read_index}]"
        if not isinstance(read, dict):
            errors.append(f"{prefix} must be an object")
            continue
        name = read.get("name")
        if not isinstance(name, str) or not name:
            errors.append(f"{prefix}.name must be a non-empty string")
        else:
            names_seen.add(name)
        if read.get("read_only") is not True:
            errors.append(f"{prefix}.read_only must be true")
        if read.get("size") != "u32":
            errors.append(f"{prefix}.size must be 'u32'")

        sample_event = sample.get("interaction_event")
        if sample_event is not None and sample_event not in ACCEPTED_INTERACTION_EVENTS:
            errors.append(
                f"samples[{sample_index}].interaction_event must be one of "
                f"{sorted(ACCEPTED_INTERACTION_EVENTS)}, got {sample_event!r}"
            )

        status = read.get("status")
        if status not in ACCEPTED_READ_STATUSES:
            errors.append(f"{prefix}.status must be one of {sorted(ACCEPTED_READ_STATUSES)}, got {status!r}")

        value = read.get("value_u32_hex")
        if value is None:
            value = read.get("value_u32")
        if status == "ok" and not is_u32_value(value):
            errors.append(f"{prefix} must include a u32 scalar value")
    for name in required_names:
        if name not in names_seen:
            errors.append(f"samples[{sample_index}].scalar_reads missing {name!r}")
    return errors


def check_samples(trace: dict[str, Any], min_samples: int) -> list[str]:
    samples = trace.get("samples")
    if not isinstance(samples, list):
        return ["samples must be a list"]
    errors: list[str] = []
    required_names = declared_scalar_names(trace)
    if len(samples) < min_samples:
        errors.append(f"samples count too low: expected at least {min_samples}, got {len(samples)}")
    for index, sample in enumerate(samples):
        if not isinstance(sample, dict):
            errors.append(f"samples[{index}] must be an object")
            continue
        errors.extend(check_scalar_read(sample, index, required_names))
    return errors


def check_trace(
    path: Path | str,
    expect_phase: str | None = None,
    min_samples: int = 0,
    expect_run_id: str | None = None,
    expect_phase_confidence: str | None = None,
) -> list[str]:
    trace, error = load_json(Path(path))
    if error:
        return [error]
    if not isinstance(trace, dict):
        return ["trace root must be an object"]

    errors: list[str] = []
    errors.extend(collect_forbidden(trace))
    if trace.get("schema") != EXPECTED_SCHEMA:
        errors.append(f"schema mismatch: expected {EXPECTED_SCHEMA!r}, got {trace.get('schema')!r}")
    errors.extend(check_sampling(trace, expect_phase, expect_run_id, expect_phase_confidence))
    errors.extend(check_samples(trace, min_samples))
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check HSL runtime scalar sampling trace metadata.")
    parser.add_argument("trace_json", type=Path)
    parser.add_argument("--expect-phase")
    parser.add_argument("--expect-run-id")
    parser.add_argument("--expect-phase-confidence")
    parser.add_argument("--min-samples", type=int, default=0)
    args = parser.parse_args(argv)

    errors = check_trace(
        args.trace_json,
        expect_phase=args.expect_phase,
        min_samples=args.min_samples,
        expect_run_id=args.expect_run_id,
        expect_phase_confidence=args.expect_phase_confidence,
    )
    if errors:
        print(f"FAIL hsl runtime trace ({len(errors)} error(s))")
        for error in errors[:MAX_PRINTED_ERRORS]:
            print(f"- {error}")
        if len(errors) > MAX_PRINTED_ERRORS:
            print(f"- ... {len(errors) - MAX_PRINTED_ERRORS} more")
        return 1
    print("PASS hsl runtime trace")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
