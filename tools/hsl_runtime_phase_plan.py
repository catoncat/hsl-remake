#!/usr/bin/env python3
"""Generate a read-only HSL runtime phase sampling plan.

The plan is a command matrix for supervised scalar traces. It does not launch,
click, type, sample, or write runtime traces by itself.
"""

from __future__ import annotations

import argparse
import json
import re
import shlex
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    from tools import hsl_runtime_probe
except (ImportError, ModuleNotFoundError):
    import hsl_runtime_probe


SCHEMA = "hsl_runtime_phase_collection_plan.v1"
RUN_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
STATIC_FINDINGS = [
    {
        "name": "script_primary_dispatch_table",
        "address": "0x453708",
        "summary": "24 slots, 24 unique probable handlers",
        "runtime_probe_use": "script_phase profile only; scalar read does not decode handler semantics",
    },
    {
        "name": "script_action_dispatch_table",
        "address": "0x4537f4",
        "summary": "140 slots, 133 unique probable handlers",
        "runtime_probe_use": "script_phase profile only; correlate later with script-vm action names",
    },
    {
        "name": "script_interpreter_bridge_candidate",
        "address": "0x450840",
        "summary": "5 CALL xrefs",
        "runtime_probe_use": "not directly sampled by u32 phase plan; informs script_phase follow-up",
    },
    {
        "name": "logical_ui_hit_test_candidate",
        "address": "0x445977",
        "summary": "1 CODE xref",
        "runtime_probe_use": "motivates logical_x/logical_y sampling across menu and click phases",
    },
]


@dataclass(frozen=True)
class PhaseSpec:
    phase_id: str
    phase_hint: str
    phase_profile: str
    interaction_event: str
    operator_setup: str
    sample_count: int
    sample_interval_ms: int
    read_timeout: int
    requires_supervision: bool


PHASE_SPECS = [
    PhaseSpec(
        "title_idle",
        "title_idle",
        "title_idle",
        "none",
        "Original runtime is at the title/menu idle surface; do not inject input while sampling.",
        10,
        100,
        4,
        True,
    ),
    PhaseSpec(
        "dialogue",
        "dialogue",
        "dialogue",
        "none",
        "Opening dialogue UI is visible and stable; do not advance text while sampling.",
        10,
        100,
        4,
        True,
    ),
    PhaseSpec(
        "player_control",
        "player_control",
        "player_control",
        "none",
        "First controllable map state is visible before opening the action menu.",
        12,
        100,
        4,
        True,
    ),
    PhaseSpec(
        "action_menu",
        "action_menu",
        "action_menu",
        "none",
        "Action menu is visible and stable; no command is highlighted by fresh input during sampling.",
        12,
        100,
        4,
        True,
    ),
    PhaseSpec(
        "confirm_down",
        "confirm_down",
        "confirm_down",
        "confirm_down",
        "Hold confirm input during this short trace. Use HID-level input; Win32 message injection is not reliable.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "confirm_up",
        "confirm_up",
        "confirm_up",
        "confirm_up",
        "Release confirm input before sampling starts, then keep the state stable.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "cancel_down",
        "cancel_down",
        "cancel_down",
        "cancel_down",
        "Hold cancel input during this short trace. Use HID-level input.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "cancel_up",
        "cancel_up",
        "cancel_up",
        "cancel_up",
        "Release cancel input before sampling starts, then keep the state stable.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "click_down",
        "click_down",
        "click_down",
        "click_down",
        "Hold mouse click at the chosen game client coordinate during this short trace.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "click_up",
        "click_up",
        "click_up",
        "click_up",
        "Release mouse click before sampling starts, then keep cursor and focus stable.",
        6,
        35,
        4,
        True,
    ),
    PhaseSpec(
        "camera_scroll",
        "camera_scroll",
        "camera_scroll",
        "manual_phase_mark",
        "Camera is visibly scrolling or immediately parked after a known scroll-triggering event.",
        16,
        100,
        4,
        True,
    ),
]
TRANSITION_SPECS = [
    {
        "priority": 1,
        "transition_id": "player_control_to_action_menu",
        "before_phase": "player_control",
        "edge_phases": ["click_down", "click_up", "confirm_down", "confirm_up"],
        "after_phase": "action_menu",
        "trigger": "open_menu",
        "operator_steps": [
            "Reach first player-controllable unit state.",
            "Run the player_control phase trace.",
            "Open the action menu with the same HID gesture used during capture runs.",
            "If feasible, run the click_down/click_up or confirm_down/confirm_up edge traces that match the actual interaction.",
            "Run the action_menu phase trace immediately after the menu is stable.",
        ],
        "requested_by": "battle-engine ActionResult phase_handoff: player_control -> action_menu",
        "claim_limit": "Can only upgrade to runtime-observed if scalar changes correlate with operator-observed menu open.",
    },
    {
        "priority": 2,
        "transition_id": "action_menu_to_move_select_and_cancel_back",
        "before_phase": "action_menu",
        "edge_phases": ["click_down", "click_up", "cancel_down", "cancel_up"],
        "after_phase": "action_menu",
        "trigger": "move_select_then_cancel_back",
        "operator_steps": [
            "Place selection on the move command if command identity is operator-observed.",
            "Run click_down/click_up around entering move_select or target selection if feasible.",
            "Cancel back from move_select with the actual cancel input.",
            "Run cancel_down/cancel_up around the cancel-back action.",
            "Run the action_menu phase trace after the menu is stable again.",
        ],
        "requested_by": "battle-engine needs action_menu -> move_select and cancel-back scalar evidence.",
        "claim_limit": "Do not claim move command identity unless command selection is separately operator-observed.",
    },
    {
        "priority": 3,
        "transition_id": "action_menu_to_attack_target_and_cancel_back",
        "before_phase": "action_menu",
        "edge_phases": ["click_down", "click_up", "cancel_down", "cancel_up"],
        "after_phase": "action_menu",
        "trigger": "attack_target_then_cancel_back",
        "operator_steps": [
            "Place selection on the attack command if command identity is operator-observed.",
            "Run click_down/click_up around entering attack_target or target selection if feasible.",
            "Cancel back from attack_target with the actual cancel input.",
            "Run cancel_down/cancel_up around the cancel-back action.",
            "Run the action_menu phase trace after the menu is stable again.",
        ],
        "requested_by": "battle-engine needs menu_state/menu_loop distinction for attack target mode.",
        "claim_limit": "Do not claim attack target mode unless menu/logical scalars change with observed target cursor state.",
    },
    {
        "priority": 4,
        "transition_id": "action_menu_to_wait_turn_handoff",
        "before_phase": "action_menu",
        "after_phase": "confirm_down",
        "operator_steps": [
            "Place selection on wait/end-turn if command identity is operator-observed.",
            "Run confirm_down/click_down and confirm_up/click_up around selection.",
            "Run player_control, camera_scroll, or script_phase profile immediately after the visible handoff.",
        ],
        "requested_by": "battle-engine provisional wait -> turn_handoff ActionResult.",
        "claim_limit": "Do not claim action consumption or turn handoff without a post-confirm scalar/phase change.",
    },
    {
        "priority": 5,
        "transition_id": "attack_target_to_action_feedback",
        "before_phase": "action_menu",
        "after_phase": "confirm_down",
        "operator_steps": [
            "Enter attack target mode with an operator-observed enemy target available.",
            "Run click_down/confirm_down on target confirm.",
            "Run click_up/confirm_up and then a short action_menu/player_control trace during immediate feedback.",
        ],
        "requested_by": "battle-engine provisional attack -> action_feedback ActionResult.",
        "claim_limit": "Do not claim damage/action feedback semantics from scalar changes alone.",
    },
    {
        "priority": 6,
        "transition_id": "turn_handoff_to_script_or_camera_phase",
        "before_phase": "confirm_up",
        "after_phase": "camera_scroll",
        "operator_steps": [
            "After wait/end-turn or event trigger, watch for camera scroll, script popup, or non-player phase.",
            "Run camera_scroll profile during visible scroll if possible.",
            "Run script_phase profile after the transition stabilizes.",
        ],
        "requested_by": "battle-engine needs ally/enemy/script/camera handoff observations.",
        "claim_limit": "script_phase static dispatch scalar reads are context only, not handler decode evidence.",
    },
]


def validate_run_id(run_id: str) -> None:
    if not run_id or not RUN_ID_RE.match(run_id):
        raise SystemExit("run_id must contain only letters, numbers, underscore, dot, or dash")


def phase_output_path(output_root: Path, run_id: str, index: int, phase_id: str) -> Path:
    return output_root / run_id / f"{index:02d}-{phase_id}.json"


def transition_output_path(output_root: Path, run_id: str, priority: int, role: str, phase_id: str) -> Path:
    return output_root / run_id / "transitions" / f"p{priority:02d}-{role}-{phase_id}.json"


def command_with_output(command: list[str], output_path: Path) -> list[str]:
    updated = list(command)
    try:
        output_index = updated.index("--output") + 1
    except ValueError:
        updated.extend(["--output", output_path.as_posix()])
    else:
        updated[output_index] = output_path.as_posix()
    return updated


def command_option(command: list[str], option: str) -> str:
    try:
        return command[command.index(option) + 1]
    except (ValueError, IndexError):
        return ""


def build_probe_argv(
    spec: PhaseSpec,
    run_id: str,
    output_path: Path,
    no_window: bool,
) -> list[str]:
    argv = [
        "python3",
        "tools/hsl_runtime_probe.py",
        "--read-backend",
        "win32-rpm",
        "--phase-profile",
        spec.phase_profile,
        "--sample-count",
        str(spec.sample_count),
        "--sample-interval-ms",
        str(spec.sample_interval_ms),
        "--read-timeout",
        str(spec.read_timeout),
        "--phase-hint",
        spec.phase_hint,
        "--phase-confidence",
        "operator_observed",
        "--interaction-event",
        spec.interaction_event,
        "--run-id",
        run_id,
        "--operator-note",
        f"supervised phase trace: {spec.phase_id}; operator label only",
        "--output",
        output_path.as_posix(),
    ]
    if no_window:
        argv.insert(2, "--no-window")
    return argv


def build_phase_entry(
    spec: PhaseSpec,
    run_id: str,
    output_root: Path,
    index: int,
    no_window: bool,
) -> dict[str, Any]:
    output_path = phase_output_path(output_root, run_id, index, spec.phase_id)
    target_specs = hsl_runtime_probe.phase_profile_specs(spec.phase_profile)
    return {
        "phase_id": spec.phase_id,
        "phase_hint": spec.phase_hint,
        "phase_profile": spec.phase_profile,
        "interaction_event": spec.interaction_event,
        "requires_supervision": spec.requires_supervision,
        "operator_setup": spec.operator_setup,
        "sample_count": spec.sample_count,
        "sample_interval_ms": spec.sample_interval_ms,
        "read_timeout": spec.read_timeout,
        "output": output_path.as_posix(),
        "scalar_names": [item["name"] for item in target_specs],
        "command_argv": build_probe_argv(spec, run_id, output_path, no_window),
    }


def build_plan(
    run_id: str,
    output_root: Path = Path("ignored/runtime-probes/phase-runs"),
    no_window: bool = False,
) -> dict[str, Any]:
    validate_run_id(run_id)
    phases = [
        build_phase_entry(spec, run_id, output_root, index + 1, no_window)
        for index, spec in enumerate(PHASE_SPECS)
    ]
    phase_by_id = {phase["phase_id"]: phase for phase in phases}
    transitions = []
    for spec in TRANSITION_SPECS:
        transition = dict(spec)
        transition["before_command_argv"] = command_with_output(
            phase_by_id[spec["before_phase"]]["command_argv"],
            transition_output_path(output_root, run_id, spec["priority"], "before", spec["before_phase"]),
        )
        transition["edge_command_argvs"] = [
            command_with_output(
                phase_by_id[phase]["command_argv"],
                transition_output_path(output_root, run_id, spec["priority"], f"edge{index + 1}", phase),
            )
            for index, phase in enumerate(spec.get("edge_phases", []))
        ]
        transition["after_command_argv"] = command_with_output(
            phase_by_id[spec["after_phase"]]["command_argv"],
            transition_output_path(output_root, run_id, spec["priority"], "after", spec["after_phase"]),
        )
        transition["evidence_tier_until_observed"] = "manual_hint_only"
        transitions.append(transition)
    return {
        "schema": SCHEMA,
        "run_id": run_id,
        "source_policy": "phase plan is tracked-safe metadata; generated traces stay under ignored/runtime-probes",
        "static_findings_context": STATIC_FINDINGS,
        "phase_count": len(phases),
        "transition_count": len(transitions),
        "phase_ids": [phase["phase_id"] for phase in phases],
        "shared_rules": [
            "phase labels are operator correlation hints, not proof of original semantics",
            "use HID-level input for confirm/cancel/click phases because Win32 message injection is ignored",
            "do not commit generated runtime traces unless curated into a compact evidence package",
        ],
        "phases": phases,
        "transitions": transitions,
    }


def check_plan(plan: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if plan.get("schema") != SCHEMA:
        errors.append(f"schema mismatch: expected {SCHEMA!r}")
    phases = plan.get("phases")
    if not isinstance(phases, list) or not phases:
        return errors + ["phases must be a non-empty list"]
    seen: set[str] = set()
    for index, phase in enumerate(phases):
        prefix = f"phases[{index}]"
        if not isinstance(phase, dict):
            errors.append(f"{prefix} must be an object")
            continue
        phase_id = phase.get("phase_id")
        if not isinstance(phase_id, str) or not phase_id:
            errors.append(f"{prefix}.phase_id must be a non-empty string")
        elif phase_id in seen:
            errors.append(f"{prefix}.phase_id duplicates {phase_id!r}")
        else:
            seen.add(phase_id)
        if phase.get("phase_profile") not in hsl_runtime_probe.PHASE_PROFILES:
            errors.append(f"{prefix}.phase_profile is not supported by hsl_runtime_probe")
        if phase.get("interaction_event") not in hsl_runtime_probe.ACCEPTED_INTERACTION_EVENTS:
            errors.append(f"{prefix}.interaction_event is not supported by hsl_runtime_probe")
        command = phase.get("command_argv")
        if not isinstance(command, list) or "tools/hsl_runtime_probe.py" not in command:
            errors.append(f"{prefix}.command_argv must call tools/hsl_runtime_probe.py")
        output = phase.get("output")
        if not isinstance(output, str) or not output.startswith("ignored/runtime-probes/"):
            errors.append(f"{prefix}.output must stay under ignored/runtime-probes")
        scalar_names = phase.get("scalar_names")
        if not isinstance(scalar_names, list) or not scalar_names:
            errors.append(f"{prefix}.scalar_names must be a non-empty list")
    expected = {spec.phase_id for spec in PHASE_SPECS}
    missing = sorted(expected - seen)
    if missing:
        errors.append(f"missing phases: {missing}")
    transitions = plan.get("transitions")
    if not isinstance(transitions, list) or not transitions:
        errors.append("transitions must be a non-empty list")
    else:
        transition_ids: set[str] = set()
        for index, transition in enumerate(transitions):
            prefix = f"transitions[{index}]"
            if not isinstance(transition, dict):
                errors.append(f"{prefix} must be an object")
                continue
            transition_id = transition.get("transition_id")
            if not isinstance(transition_id, str) or not transition_id:
                errors.append(f"{prefix}.transition_id must be a non-empty string")
            elif transition_id in transition_ids:
                errors.append(f"{prefix}.transition_id duplicates {transition_id!r}")
            else:
                transition_ids.add(transition_id)
            if transition.get("before_phase") not in seen:
                errors.append(f"{prefix}.before_phase must reference a known phase")
            if transition.get("after_phase") not in seen:
                errors.append(f"{prefix}.after_phase must reference a known phase")
            steps = transition.get("operator_steps")
            if not isinstance(steps, list) or not steps:
                errors.append(f"{prefix}.operator_steps must be a non-empty list")
            for key in ("before_command_argv", "after_command_argv"):
                command = transition.get(key)
                if not isinstance(command, list) or "tools/hsl_runtime_probe.py" not in command:
                    errors.append(f"{prefix}.{key} must call tools/hsl_runtime_probe.py")
            edge_commands = transition.get("edge_command_argvs")
            if edge_commands is not None:
                if not isinstance(edge_commands, list):
                    errors.append(f"{prefix}.edge_command_argvs must be a list when present")
                else:
                    for command_index, command in enumerate(edge_commands):
                        if not isinstance(command, list) or "tools/hsl_runtime_probe.py" not in command:
                            errors.append(f"{prefix}.edge_command_argvs[{command_index}] must call tools/hsl_runtime_probe.py")
    return errors


def write_plan(plan: dict[str, Any], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def shell_join(argv: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in argv)


def parse_priority_filter(value: str | None) -> set[int] | None:
    if value is None or value == "":
        return None
    priorities: set[int] = set()
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start_text, end_text = part.split("-", 1)
            start = int(start_text)
            end = int(end_text)
            if end < start:
                raise SystemExit(f"invalid --priority range: {part}")
            priorities.update(range(start, end + 1))
        else:
            priorities.add(int(part))
    if not priorities:
        raise SystemExit("invalid --priority filter")
    return priorities


def selected_transitions(plan: dict[str, Any], priorities: set[int] | None) -> list[dict[str, Any]]:
    if priorities is None:
        return list(plan["transitions"])
    selected = [transition for transition in plan["transitions"] if transition["priority"] in priorities]
    if not selected:
        raise SystemExit(f"priority filter {sorted(priorities)} did not match phase plan")
    return selected


def transition_report_argv(transition: dict[str, Any], allow_pending: bool = True) -> list[str]:
    argv = [
        "python3",
        "tools/hsl_runtime_transition_report.py",
        "--transition-id",
        transition["transition_id"],
        "--before",
        transition["before_command_argv"][-1],
        "--after",
        transition["after_command_argv"][-1],
    ]
    for command in transition.get("edge_command_argvs", []):
        argv.extend(["--edge", command[-1]])
    if allow_pending:
        argv.append("--allow-pending")
    return argv


def print_shell_commands(plan: dict[str, Any], priorities: set[int] | None = None) -> None:
    print(f"# HSL runtime phase collection commands")
    print(f"# run_id={plan['run_id']}")
    print("# Execute only when the operator-visible phase matches the heading.")
    print("# Labels are correlation hints, not semantic proof.")
    selected = selected_transitions(plan, priorities)
    selected_commands: list[list[str]] = []
    for transition in selected:
        print()
        print(f"# priority {transition['priority']}: {transition['transition_id']}")
        if "trigger" in transition:
            print(f"# trigger: {transition['trigger']}")
        for step in transition["operator_steps"]:
            print(f"# - {step}")
        print(shell_join(transition["before_command_argv"]))
        selected_commands.append(transition["before_command_argv"])
        if transition.get("edge_command_argvs"):
            print("# Optional edge traces; run only the edge that matches the actual interaction:")
            for command in transition["edge_command_argvs"]:
                print(shell_join(command))
                selected_commands.append(command)
        print(shell_join(transition["after_command_argv"]))
        selected_commands.append(transition["after_command_argv"])
    print()
    trace_paths = [command_option(command, "--output") for command in selected_commands]
    print("# After collecting traces, run:")
    for command in selected_commands:
        print(
            shell_join(
                [
                    "python3",
                    "tools/hsl_runtime_trace_check.py",
                    command_option(command, "--output"),
                    "--expect-phase",
                    command_option(command, "--phase-hint"),
                    "--expect-run-id",
                    plan["run_id"],
                    "--min-samples",
                    command_option(command, "--sample-count"),
                ]
            )
        )
    print(shell_join(["python3", "tools/hsl_runtime_trace_set_check.py", "--expect-run-id", plan["run_id"], "--min-traces", "1", *trace_paths]))
    print()
    print("# Transition delta reports. Keep --allow-pending before traces exist; remove it for strict completed-trace reporting.")
    for transition in selected:
        print(shell_join(transition_report_argv(transition, allow_pending=True)))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--output-root", type=Path, default=Path("ignored/runtime-probes/phase-runs"))
    parser.add_argument("--output", type=Path, default=Path("ignored/runtime-probes/latest/phase-plan.json"))
    parser.add_argument("--no-window", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--print-shell", action="store_true")
    parser.add_argument(
        "--priority",
        help="With --print-shell, print selected transition priorities, e.g. 1, 1-3, or 1,3.",
    )
    args = parser.parse_args(argv)

    plan = build_plan(args.run_id, output_root=args.output_root, no_window=args.no_window)
    errors = check_plan(plan)
    if errors:
        print(f"FAIL hsl runtime phase plan ({len(errors)} error(s))")
        for error in errors:
            print(f"- {error}")
        return 1
    if args.check:
        print("PASS hsl runtime phase plan")
        return 0
    if args.print_shell:
        print_shell_commands(plan, priorities=parse_priority_filter(args.priority))
        return 0
    write_plan(plan, args.output)
    print(f"wrote runtime phase plan: {args.output}")
    print(f"phase_count: {plan['phase_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
