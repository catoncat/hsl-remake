#!/usr/bin/env python3
"""Summarize scalar deltas for a supervised HSL runtime transition."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any

try:
    from tools import hsl_runtime_phase_plan, hsl_runtime_trace_check, hsl_runtime_trace_set_check
except (ImportError, ModuleNotFoundError):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import hsl_runtime_phase_plan
    import hsl_runtime_trace_check
    import hsl_runtime_trace_set_check


def load_checked_trace(path: Path) -> tuple[dict[str, Any] | None, list[str]]:
    errors = hsl_runtime_trace_check.check_trace(path)
    if errors:
        return None, errors
    trace, error = hsl_runtime_trace_check.load_json(path)
    if error:
        return None, [error]
    if not isinstance(trace, dict):
        return None, ["trace root must be an object"]
    return trace, []


def phase_hint(trace: dict[str, Any]) -> str:
    sampling = trace.get("sampling")
    if isinstance(sampling, dict) and isinstance(sampling.get("phase_hint"), str):
        return sampling["phase_hint"]
    return "unknown"


def trace_run_id(trace: dict[str, Any]) -> str | None:
    sampling = trace.get("sampling")
    if isinstance(sampling, dict) and isinstance(sampling.get("run_id"), str):
        return sampling["run_id"]
    return None


def scalar_value_counts(trace: dict[str, Any]) -> dict[str, dict[str, int]]:
    counts: dict[str, Counter[str]] = {}
    for sample in trace.get("samples", []):
        if not isinstance(sample, dict):
            continue
        for read in sample.get("scalar_reads", []):
            if not isinstance(read, dict):
                continue
            if read.get("status") != "ok":
                continue
            name = read.get("name")
            if not isinstance(name, str) or not name:
                continue
            value = read.get("value_u32_hex")
            if value is None:
                value = read.get("value_u32")
            value_hex = hsl_runtime_trace_set_check.normalized_u32_hex(value)
            if value_hex is None:
                continue
            counts.setdefault(name, Counter())[value_hex] += 1
    return {name: dict(sorted(counter.items())) for name, counter in sorted(counts.items())}


def dominant_value(value_counts: dict[str, int]) -> str | None:
    if not value_counts:
        return None
    return sorted(value_counts.items(), key=lambda item: (-item[1], item[0]))[0][0]


def compare_values(before: dict[str, dict[str, int]], after: dict[str, dict[str, int]]) -> dict[str, Any]:
    changed: dict[str, dict[str, str | None]] = {}
    stable: dict[str, str | None] = {}
    missing_before: list[str] = []
    missing_after: list[str] = []
    for name in sorted(set(before) | set(after)):
        before_value = dominant_value(before.get(name, {}))
        after_value = dominant_value(after.get(name, {}))
        if before_value is None:
            missing_before.append(name)
        if after_value is None:
            missing_after.append(name)
        if before_value is not None and after_value is not None:
            if before_value == after_value:
                stable[name] = before_value
            else:
                changed[name] = {"before": before_value, "after": after_value}
    return {
        "changed": changed,
        "stable": stable,
        "missing_before": missing_before,
        "missing_after": missing_after,
    }


def build_report(
    before_path: Path,
    after_path: Path,
    edge_paths: list[Path],
    transition_id: str,
    require_same_run_id: bool = True,
    allow_pending: bool = False,
) -> tuple[dict[str, Any] | None, list[str]]:
    traces: list[tuple[str, Path, dict[str, Any]]] = []
    errors: list[str] = []
    for role, path in [("before", before_path), ("after", after_path), *[("edge", path) for path in edge_paths]]:
        trace, trace_errors = load_checked_trace(path)
        if trace_errors:
            errors.extend(f"{role}:{path.name}: {error}" for error in trace_errors)
            continue
        assert trace is not None
        traces.append((role, path, trace))
    if errors and allow_pending:
        return {
            "schema": "hsl_runtime_transition_report.v1",
            "transition_id": transition_id,
            "run_id": None,
            "evidence_tier": "manual_hint_only",
            "status": "pending_traces",
            "missing_or_invalid_traces": errors,
            "claim_limit": "No runtime-observed transition evidence; required traces are missing or invalid.",
            "required_traces": {
                "before": before_path.as_posix(),
                "after": after_path.as_posix(),
                "edges": [path.as_posix() for path in edge_paths],
            },
        }, []
    if errors:
        return None, errors

    run_ids = [trace_run_id(trace) for _role, _path, trace in traces]
    present_run_ids = {run_id for run_id in run_ids if run_id is not None}
    if require_same_run_id and len(present_run_ids) != 1:
        return None, [f"expected exactly one run_id across traces, got {sorted(present_run_ids)}"]

    before_trace = next(trace for role, _path, trace in traces if role == "before")
    after_trace = next(trace for role, _path, trace in traces if role == "after")
    before_values = scalar_value_counts(before_trace)
    after_values = scalar_value_counts(after_trace)
    comparison = compare_values(before_values, after_values)

    evidence_tier = "runtime-observed" if comparison["changed"] else "operator_observed_no_scalar_delta"
    return {
        "schema": "hsl_runtime_transition_report.v1",
        "transition_id": transition_id,
        "run_id": sorted(present_run_ids)[0] if present_run_ids else None,
        "evidence_tier": evidence_tier,
        "claim_limit": "Scalar deltas support phase correlation only; command identity/action consumption need independent evidence.",
        "before": {
            "path": before_path.as_posix(),
            "phase_hint": phase_hint(before_trace),
            "value_counts": before_values,
        },
        "after": {
            "path": after_path.as_posix(),
            "phase_hint": phase_hint(after_trace),
            "value_counts": after_values,
        },
        "edges": [
            {
                "path": path.as_posix(),
                "phase_hint": phase_hint(trace),
                "value_counts": scalar_value_counts(trace),
            }
            for role, path, trace in traces
            if role == "edge"
        ],
        "scalar_delta": comparison,
    }, []


def output_path_from_probe_argv(command: list[str]) -> Path:
    try:
        return Path(command[command.index("--output") + 1])
    except (ValueError, IndexError) as exc:
        raise ValueError(f"probe command is missing --output: {command!r}") from exc


def build_report_from_transition(
    transition: dict[str, Any],
    allow_pending: bool,
) -> tuple[dict[str, Any] | None, list[str]]:
    try:
        before_path = output_path_from_probe_argv(transition["before_command_argv"])
        after_path = output_path_from_probe_argv(transition["after_command_argv"])
        edge_paths = [
            output_path_from_probe_argv(command)
            for command in transition.get("edge_command_argvs", [])
        ]
    except (KeyError, TypeError, ValueError) as exc:
        return None, [f"{transition.get('transition_id', '<unknown>')}: invalid transition plan: {exc}"]
    return build_report(
        before_path,
        after_path,
        edge_paths,
        transition["transition_id"],
        allow_pending=allow_pending,
    )


def summarize_report_set(reports: list[dict[str, Any]]) -> str:
    statuses = {str(report.get("status", "complete")) for report in reports}
    if not reports:
        return "empty"
    if statuses == {"complete"}:
        return "complete"
    if statuses == {"pending_traces"}:
        return "pending_traces"
    return "mixed"


def missing_trace_items(report: dict[str, Any]) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    for missing in report.get("missing_or_invalid_traces", []):
        if not isinstance(missing, str):
            continue
        role, _sep, detail = missing.partition(":")
        filename, _sep, error = detail.partition(": ")
        items.append(
            {
                "transition_id": report.get("transition_id"),
                "priority": report.get("priority"),
                "trigger": report.get("trigger"),
                "role": role,
                "file": filename,
                "error": error or detail,
            }
        )
    return items


def list_missing_traces(report: dict[str, Any]) -> list[dict[str, Any]]:
    if report.get("schema") == "hsl_runtime_transition_report_set.v1":
        items: list[dict[str, Any]] = []
        for child in report.get("reports", []):
            if isinstance(child, dict):
                items.extend(missing_trace_items(child))
        return items
    return missing_trace_items(report)


def print_missing_traces(report: dict[str, Any]) -> None:
    items = list_missing_traces(report)
    if not items:
        print("PASS no missing transition traces")
        return
    for item in items:
        print(
            "\t".join(
                [
                    f"priority={item.get('priority')}",
                    f"transition={item.get('transition_id')}",
                    f"trigger={item.get('trigger')}",
                    f"role={item.get('role')}",
                    f"file={item.get('file')}",
                    f"error={item.get('error')}",
                ]
            )
        )


def planned_trace_commands(plan: dict[str, Any], priority: str | None) -> list[dict[str, Any]]:
    priorities = hsl_runtime_phase_plan.parse_priority_filter(priority)
    commands: list[dict[str, Any]] = []
    for transition in hsl_runtime_phase_plan.selected_transitions(plan, priorities):
        command_entries = [
            ("before", transition["before_phase"], transition["before_command_argv"]),
            *[
                (f"edge{index + 1}", phase, command)
                for index, (phase, command) in enumerate(
                    zip(transition.get("edge_phases", []), transition.get("edge_command_argvs", []))
                )
            ],
            ("after", transition["after_phase"], transition["after_command_argv"]),
        ]
        for role, phase, command in command_entries:
            commands.append(
                {
                    "priority": transition["priority"],
                    "transition_id": transition["transition_id"],
                    "trigger": transition.get("trigger"),
                    "role": role,
                    "phase": phase,
                    "output": output_path_from_probe_argv(command).as_posix(),
                    "command_argv": command,
                }
            )
    return commands


def first_missing_planned_command(
    run_id: str,
    output_root: Path,
    priority: str | None,
    no_window: bool,
) -> tuple[dict[str, Any] | None, list[str]]:
    plan = hsl_runtime_phase_plan.build_plan(run_id, output_root=output_root, no_window=no_window)
    plan_errors = hsl_runtime_phase_plan.check_plan(plan)
    if plan_errors:
        return None, plan_errors
    for item in planned_trace_commands(plan, priority):
        errors = hsl_runtime_trace_check.check_trace(Path(item["output"]))
        if errors:
            item["check_error"] = errors[0]
            return item, []
    return None, []


def print_next_command(item: dict[str, Any] | None) -> None:
    if item is None:
        print("PASS no missing transition traces")
        return
    print(f"# priority {item['priority']}: {item['transition_id']}")
    print(f"# trigger: {item.get('trigger')}")
    print(f"# role: {item['role']}; phase: {item['phase']}")
    print(f"# output: {item['output']}")
    print(f"# current check: {item.get('check_error')}")
    print(hsl_runtime_phase_plan.shell_join(item["command_argv"]))


def build_collected_summary(
    run_id: str,
    output_root: Path,
    priority: str | None,
    no_window: bool,
) -> tuple[dict[str, Any] | None, list[str]]:
    plan = hsl_runtime_phase_plan.build_plan(run_id, output_root=output_root, no_window=no_window)
    plan_errors = hsl_runtime_phase_plan.check_plan(plan)
    if plan_errors:
        return None, plan_errors
    transitions: dict[str, dict[str, Any]] = {}
    for item in planned_trace_commands(plan, priority):
        transition_id = item["transition_id"]
        bucket = transitions.setdefault(
            transition_id,
            {
                "priority": item["priority"],
                "transition_id": transition_id,
                "trigger": item.get("trigger"),
                "total": 0,
                "collected": 0,
                "missing_or_invalid": 0,
                "missing_roles": [],
            },
        )
        bucket["total"] += 1
        errors = hsl_runtime_trace_check.check_trace(Path(item["output"]))
        if errors:
            bucket["missing_or_invalid"] += 1
            bucket["missing_roles"].append(
                {
                    "role": item["role"],
                    "phase": item["phase"],
                    "output": item["output"],
                    "error": errors[0],
                }
            )
        else:
            bucket["collected"] += 1
    transition_list = sorted(transitions.values(), key=lambda entry: entry["priority"])
    total = sum(entry["total"] for entry in transition_list)
    collected = sum(entry["collected"] for entry in transition_list)
    missing_or_invalid = sum(entry["missing_or_invalid"] for entry in transition_list)
    status = "complete" if total > 0 and missing_or_invalid == 0 else "pending_traces"
    return {
        "schema": "hsl_runtime_transition_collection_summary.v1",
        "run_id": run_id,
        "status": status,
        "priority_filter": priority,
        "total": total,
        "collected": collected,
        "missing_or_invalid": missing_or_invalid,
        "transitions": transition_list,
        "claim_limit": "Collection summary only checks trace presence/validity; it does not prove transition semantics.",
    }, []


def print_collected_summary(summary: dict[str, Any]) -> None:
    print(
        "\t".join(
            [
                f"status={summary['status']}",
                f"run_id={summary['run_id']}",
                f"collected={summary['collected']}/{summary['total']}",
                f"missing_or_invalid={summary['missing_or_invalid']}",
            ]
        )
    )
    for transition in summary["transitions"]:
        print(
            "\t".join(
                [
                    f"priority={transition['priority']}",
                    f"transition={transition['transition_id']}",
                    f"trigger={transition.get('trigger')}",
                    f"collected={transition['collected']}/{transition['total']}",
                    f"missing_or_invalid={transition['missing_or_invalid']}",
                ]
            )
        )


def build_report_set_from_plan(
    run_id: str,
    output_root: Path,
    priority: str | None,
    allow_pending: bool,
    no_window: bool = False,
) -> tuple[dict[str, Any] | None, list[str]]:
    plan = hsl_runtime_phase_plan.build_plan(run_id, output_root=output_root, no_window=no_window)
    plan_errors = hsl_runtime_phase_plan.check_plan(plan)
    if plan_errors:
        return None, plan_errors
    priorities = hsl_runtime_phase_plan.parse_priority_filter(priority)
    transitions = hsl_runtime_phase_plan.selected_transitions(plan, priorities)
    reports: list[dict[str, Any]] = []
    errors: list[str] = []
    for transition in transitions:
        report, report_errors = build_report_from_transition(transition, allow_pending=allow_pending)
        if report_errors:
            errors.extend(report_errors)
            continue
        assert report is not None
        report["priority"] = transition["priority"]
        report["trigger"] = transition.get("trigger")
        report["requested_by"] = transition.get("requested_by")
        reports.append(report)
    if errors:
        return None, errors
    return {
        "schema": "hsl_runtime_transition_report_set.v1",
        "run_id": run_id,
        "source_plan_schema": hsl_runtime_phase_plan.SCHEMA,
        "status": summarize_report_set(reports),
        "priority_filter": priority,
        "report_count": len(reports),
        "claim_limit": "Report set is a capture/report contract until operator-observed traces exist; scalar deltas do not prove command identity or action consumption.",
        "reports": reports,
    }, []


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--transition-id")
    parser.add_argument("--before", type=Path)
    parser.add_argument("--after", type=Path)
    parser.add_argument("--edge", action="append", type=Path, default=[])
    parser.add_argument("--out", type=Path)
    parser.add_argument("--allow-pending", action="store_true")
    parser.add_argument(
        "--list-missing",
        action="store_true",
        help="Print a tab-separated missing/invalid trace checklist instead of JSON. Implies --allow-pending.",
    )
    parser.add_argument(
        "--next-command",
        action="store_true",
        help="With --from-plan, print the first missing/invalid planned probe command instead of JSON.",
    )
    parser.add_argument(
        "--check-collected",
        action="store_true",
        help="With --from-plan, print collected vs missing trace counts for selected priorities.",
    )
    parser.add_argument(
        "--from-plan",
        action="store_true",
        help="Build a transition report set from hsl_runtime_phase_plan paths instead of manual --before/--after paths.",
    )
    parser.add_argument("--run-id", help="Run id for --from-plan.")
    parser.add_argument(
        "--priority",
        help="With --from-plan, select transition priorities, e.g. 1, 1-3, or 1,3.",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("ignored/runtime-probes/phase-runs"),
        help="Phase-plan output root used to derive trace paths.",
    )
    parser.add_argument("--no-window", action="store_true", help="Match phase-plan probe commands that include --no-window.")
    args = parser.parse_args(argv)

    if args.next_command:
        if not args.from_plan:
            parser.error("--next-command requires --from-plan")
        if not args.run_id:
            parser.error("--next-command requires --run-id")
        item, errors = first_missing_planned_command(
            args.run_id,
            args.output_root,
            args.priority,
            no_window=args.no_window,
        )
        if errors:
            print(f"FAIL hsl runtime transition report ({len(errors)} error(s))", file=sys.stderr)
            for error in errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        print_next_command(item)
        return 0

    if args.check_collected:
        if not args.from_plan:
            parser.error("--check-collected requires --from-plan")
        if not args.run_id:
            parser.error("--check-collected requires --run-id")
        summary, errors = build_collected_summary(
            args.run_id,
            args.output_root,
            args.priority,
            no_window=args.no_window,
        )
        if errors:
            print(f"FAIL hsl runtime transition report ({len(errors)} error(s))", file=sys.stderr)
            for error in errors:
                print(f"- {error}", file=sys.stderr)
            return 1
        assert summary is not None
        print_collected_summary(summary)
        return 0

    if args.from_plan:
        if not args.run_id:
            parser.error("--from-plan requires --run-id")
        report, errors = build_report_set_from_plan(
            args.run_id,
            args.output_root,
            args.priority,
            args.allow_pending or args.list_missing,
            no_window=args.no_window,
        )
    else:
        if not args.transition_id or args.before is None or args.after is None:
            parser.error("manual mode requires --transition-id, --before, and --after")
        report, errors = build_report(
            args.before,
            args.after,
            args.edge,
            args.transition_id,
            allow_pending=args.allow_pending or args.list_missing,
        )
    if errors:
        print(f"FAIL hsl runtime transition report ({len(errors)} error(s))", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    assert report is not None
    if args.list_missing:
        print_missing_traces(report)
        return 0
    text = json.dumps(report, indent=2, sort_keys=True)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(text + "\n", encoding="utf-8")
        print(f"wrote runtime transition report: {args.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
