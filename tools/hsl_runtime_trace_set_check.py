#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

try:
    from tools import hsl_runtime_trace_check
except (ImportError, ModuleNotFoundError):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import hsl_runtime_trace_check


MAX_PRINTED_ERRORS = 8


def load_trace(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    trace, error = hsl_runtime_trace_check.load_json(path)
    if error:
        return None, error.replace(str(path), path.name)
    if not isinstance(trace, dict):
        return None, "trace root must be an object"
    return trace, None


def normalized_u32_hex(value: Any) -> str | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        parsed = value
    elif isinstance(value, str):
        try:
            parsed = int(value, 16 if value.lower().startswith("0x") else 10)
        except ValueError:
            return None
    else:
        return None
    if not 0 <= parsed <= 0xFFFFFFFF:
        return None
    return f"0x{parsed:08x}"


def trace_run_id(trace: dict[str, Any]) -> str | None:
    source_policy = trace.get("source_policy")
    if isinstance(source_policy, dict):
        run_id = source_policy.get("run_id")
        if isinstance(run_id, str):
            return run_id
    sampling = trace.get("sampling")
    if isinstance(sampling, dict):
        run_id = sampling.get("run_id")
        if isinstance(run_id, str):
            return run_id
    return None


def sorted_counter(counter: Counter[str]) -> dict[str, int]:
    return {key: counter[key] for key in sorted(counter)}


def empty_scalar_bucket() -> dict[str, Counter[str]]:
    return {"status_counts": Counter(), "value_counts": Counter()}


def add_trace_to_summary(
    summary_state: dict[str, Any],
    trace: dict[str, Any],
) -> None:
    sampling = trace.get("sampling", {})
    phase_hint = sampling.get("phase_hint") if isinstance(sampling, dict) else None
    if isinstance(phase_hint, str):
        summary_state["phases"].add(phase_hint)

    phase_confidence = sampling.get("phase_confidence") if isinstance(sampling, dict) else None
    if isinstance(phase_confidence, str):
        summary_state["phase_confidences"][phase_confidence] += 1

    phase_profile = sampling.get("phase_profile") if isinstance(sampling, dict) else None
    if isinstance(phase_profile, str) and phase_profile:
        summary_state["phase_profiles"][phase_profile] += 1

    interaction_event = sampling.get("interaction_event") if isinstance(sampling, dict) else None
    if isinstance(interaction_event, dict):
        event_name = interaction_event.get("name")
        if isinstance(event_name, str) and event_name:
            summary_state["interaction_events"][event_name] += 1

    run_id = trace_run_id(trace)
    if run_id is not None:
        summary_state["run_ids"].add(run_id)

    samples = trace.get("samples", [])
    if not isinstance(samples, list):
        return

    for sample in samples:
        if not isinstance(sample, dict):
            continue
        sample_phase = sample.get("phase_hint")
        phase = sample_phase if isinstance(sample_phase, str) and sample_phase else phase_hint
        if not isinstance(phase, str) or not phase:
            phase = "unknown"
        summary_state["phases"].add(phase)

        sample_event = sample.get("interaction_event")
        if isinstance(sample_event, str) and sample_event:
            summary_state["sample_interaction_events"][sample_event] += 1

        scalar_reads = sample.get("scalar_reads", [])
        if not isinstance(scalar_reads, list):
            continue
        for read in scalar_reads:
            if not isinstance(read, dict):
                continue
            if read.get("size") != "u32":
                continue
            name = read.get("name")
            if not isinstance(name, str) or not name:
                continue
            status = read.get("status")
            status_text = status if isinstance(status, str) and status else "unknown"
            summary_state["scalar_names"].add(name)
            bucket = summary_state["per_phase"][phase][name]
            bucket["status_counts"][status_text] += 1

            value = read.get("value_u32_hex")
            if value is None:
                value = read.get("value_u32")
            value_hex = normalized_u32_hex(value)
            if value_hex is not None:
                bucket["value_counts"][value_hex] += 1


def finalize_summary(summary_state: dict[str, Any], trace_count: int) -> dict[str, Any]:
    per_phase: dict[str, dict[str, dict[str, dict[str, int]]]] = {}
    for phase in sorted(summary_state["per_phase"]):
        per_phase[phase] = {}
        for name in sorted(summary_state["per_phase"][phase]):
            bucket = summary_state["per_phase"][phase][name]
            per_phase[phase][name] = {
                "status_counts": sorted_counter(bucket["status_counts"]),
                "value_counts": sorted_counter(bucket["value_counts"]),
            }

    return {
        "trace_count": trace_count,
        "run_ids": sorted(summary_state["run_ids"]),
        "phases": sorted(summary_state["phases"]),
        "phase_profiles": sorted_counter(summary_state["phase_profiles"]),
        "phase_confidences": sorted_counter(summary_state["phase_confidences"]),
        "interaction_events": sorted_counter(summary_state["interaction_events"]),
        "sample_interaction_events": sorted_counter(summary_state["sample_interaction_events"]),
        "scalar_names": sorted(summary_state["scalar_names"]),
        "per_phase": per_phase,
    }


def check_trace_set(
    trace_paths: list[Path],
    expect_run_id: str | None = None,
    min_traces: int = 0,
) -> tuple[dict[str, Any] | None, list[str]]:
    errors: list[str] = []
    if len(trace_paths) < min_traces:
        errors.append(f"trace count too low: expected at least {min_traces}, got {len(trace_paths)}")

    traces: list[dict[str, Any]] = []
    for path in trace_paths:
        trace_errors = hsl_runtime_trace_check.check_trace(path)
        if trace_errors:
            safe_errors = [error.replace(str(path), path.name) for error in trace_errors]
            errors.extend(f"{path.name}: {error}" for error in safe_errors)
            continue
        trace, error = load_trace(path)
        if error:
            errors.append(f"{path.name}: {error}")
            continue
        traces.append(trace)

    if errors:
        return None, errors

    run_ids = [trace_run_id(trace) for trace in traces]
    present_run_ids = {run_id for run_id in run_ids if run_id is not None}
    if expect_run_id is not None:
        for index, run_id in enumerate(run_ids):
            if run_id != expect_run_id:
                errors.append(
                    f"expected run_id {expect_run_id!r} for trace {index + 1}, got {run_id!r}"
                )
    elif len(present_run_ids) > 1:
        errors.append(f"run_id mismatch across trace set: {sorted(present_run_ids)}")

    if errors:
        return None, errors

    summary_state: dict[str, Any] = {
        "run_ids": set(),
        "phases": set(),
        "phase_profiles": Counter(),
        "phase_confidences": Counter(),
        "interaction_events": Counter(),
        "sample_interaction_events": Counter(),
        "scalar_names": set(),
        "per_phase": defaultdict(lambda: defaultdict(empty_scalar_bucket)),
    }
    for trace in traces:
        add_trace_to_summary(summary_state, trace)
    return finalize_summary(summary_state, len(traces)), []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Summarize and correlate HSL runtime scalar trace sets.")
    parser.add_argument("trace_json", nargs="+", type=Path)
    parser.add_argument("--expect-run-id")
    parser.add_argument("--min-traces", type=int, default=0)
    args = parser.parse_args(argv)

    summary, errors = check_trace_set(
        args.trace_json,
        expect_run_id=args.expect_run_id,
        min_traces=args.min_traces,
    )
    if errors:
        print(f"FAIL hsl runtime trace set ({len(errors)} error(s))", file=sys.stderr)
        for error in errors[:MAX_PRINTED_ERRORS]:
            print(f"- {error}", file=sys.stderr)
        if len(errors) > MAX_PRINTED_ERRORS:
            print(f"- ... {len(errors) - MAX_PRINTED_ERRORS} more", file=sys.stderr)
        return 1

    print(json.dumps(summary, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
