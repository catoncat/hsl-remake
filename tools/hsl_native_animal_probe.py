#!/usr/bin/env python3
"""Probe the original ANIMAL attack dispatcher prefix with synthetic inputs.

Execute from 0x401c20 to the shared presentation tail at 0x4034c6. That tail,
resource loading, host calls and rendering are NOT executed. This is a bounded
instruction-slice observation, not a full native function/gameplay replay.
Optional analysis dependency: unicorn==2.1.4. No unknown callee is stubbed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

from hsltools.native.animal_dispatcher import ENTRY, STOP
from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ORIGINAL_EXE

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "docs/evidence_packets/static_reverse/animal_program_execution.json"
ANCHORS = {
    0x401F3B: (36, "load program cursor, consume 32-bit opcode, dispatch 0..33"),
    0x402278: (18, "some commands drain the following opcode in the same invocation"),
    0x402295: (21, "aniOver enters phase 101 and saves cursor"),
    0x4022AA: (33, "aniDelay stores phase 1, counter and continuation, then yields"),
    0x40243D: (22, "aniSetShape updates frame and yields after optional afterimage call"),
    0x402476: (35, "aniSetZoom writes both scales and yields"),
    0x402714: (34, "wait decrements, clears state on <=0, and still yields"),
}


def probe(exe: Path) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
    from hsltools.assets.animal_programs import build

    resource = build()
    for name, expected in (("aniOver", 0), ("aniDelay", 1), ("aniSetZoom", 9)):
        if resource["opcode_definitions"][name]["value"] != expected:
            raise ValueError(f"Original opcode definition changed: {name}")
    base, mapped = image(exe.read_bytes())
    # These programs test the genuine dispatcher and its delayed continuation.
    cases = [{"name": f"delay_{delay}", "words": [1, delay, 9, 0x13000, 0]}
             for delay in (0, 1, 2, 12, 30)]
    source_actor = next(row for row in resource["records"] if row["code"] == "SID_PLAYER5")
    zooms = [row for row in source_actor["programs"]["action"] if row["op"] == "aniSetZoom"]
    cases.append({"name": "player5_consecutive_zoom_excerpt",
                  "source_lines": [row["source_line"] for row in zooms],
                  "words": [value for row in zooms for value in (row["opcode"], *row["args"])] + [0]})
    for case in cases:
        machine = Uc(UC_ARCH_X86, UC_MODE_32)
        machine.mem_map(base, len(mapped))
        machine.mem_write(base, bytes(mapped))
        machine.mem_map(0x10000000, 0x10000)
        machine.mem_map(0x20000000, 0x2000)
        obj, program, stack = 0x20000000, 0x20001000, 0x1000FF00

        def put(address: int, value: int) -> None:
            machine.mem_write(address, struct.pack("<I", value & 0xFFFFFFFF))

        def get(offset: int) -> int:
            return struct.unpack("<I", machine.mem_read(obj + offset, 4))[0]

        def state() -> dict:
            return {"cursor_word": (get(0xA4) - program) // 4,
                    "phase": get(0x8C) >> 16,
                    "wait": struct.unpack("<i", machine.mem_read(obj + 0xA0, 4))[0],
                    "zoom_x": get(0x20), "zoom_y": get(0x24)}

        def guard(_machine, address, _size, _data):
            if not ENTRY <= address < STOP:
                raise RuntimeError(f"Unmodelled native callee {address:#x}; probe does not stub functions")

        machine.hook_add(UC_HOOK_CODE, guard)
        put(obj + 0xA4, program)
        put(obj + 0x20, 0x10000)
        put(obj + 0x24, 0x10000)
        for index, word in enumerate(case["words"]):
            put(program + index * 4, word)
        case["states"] = [state()]
        for _ in range(64):
            # Normal update mode (0), not the initialization flag 0x20000000.
            put(stack, 0x10000000)
            put(stack + 4, obj)
            put(stack + 8, 0)
            machine.reg_write(UC_X86_REG_ESP, stack)
            machine.emu_start(ENTRY, STOP, count=512)
            if machine.reg_read(UC_X86_REG_EIP) != STOP:
                raise RuntimeError("Dispatcher prefix exceeded 512 instructions")
            case["states"].append(state())
            if case["states"][-1]["phase"] == 101:
                break
        else:
            raise RuntimeError("Synthetic program exceeded 64 updates")
    # Read raw tables, not r2-generated labels (which may point to misleading names).
    opcode_targets = struct.unpack_from("<34I", mapped, 0x4037B0 - base)
    phase_targets = struct.unpack_from("<10I", mapped, 0x403720 - base)
    return {"schema": "hsl_native_animal_instruction_slice.v1", "evidence_tier": "static-derived",
            "exe_sha256": EXE_SHA, "entry": hex(ENTRY), "stop_before": hex(STOP),
            "instruction_budget_per_update": 512, "update_budget_per_case": 64,
            "source_program_sha256": resource["sources"]["programs"]["sha256"],
            "source_header_sha256": resource["sources"]["opcodes"]["sha256"],
            "prefix_sha256": hashlib.sha256(mapped[ENTRY-base:STOP-base]).hexdigest(),
            "instruction_anchors": [{"address": hex(address), "bytes": bytes(mapped[address-base:address-base+size]).hex(),
                                     "meaning": meaning} for address, (size, meaning) in ANCHORS.items()],
            "opcode_table": {"address": "0x4037b0", "targets": [hex(v) for v in opcode_targets]},
            "phase_table": {"address": "0x403720", "targets": [hex(v) for v in phase_targets]},
            "phase_indices": {str(i): mapped[0x403748-base+i] for i in (0, 1, 8, 12, 13, 101, 102, 103)},
            "cases": cases,
            "limits": ["Synthetic object, script pointer and update calls; native loader/initialization not executed.",
                       "aniOver 0 appended to synthetic excerpts for bounded termination; not evidence of parser padding.",
                       "Stop at the common presentation tail: no position integration, sound, graphics or full function return.",
                       "Only aniDelay, aniSetZoom and aniOver are exercised; all unknown callees fail explicitly.",
                       "Source opcode numeric definitions are separate from this process's supported handler subset.",
                       "No update frequency, original frame duration, complete attack/casting or Godot parity claim."]}


def validate_observations(packet: dict) -> None:
    """Cross-check observed transitions against independent expected counts."""
    for case in packet["cases"]:
        states = case["states"]
        if case["name"].startswith("delay_"):
            delay = case["words"][1]
            expected_zoom_update = max(delay, 1) + 2
            indices = [i for i, state in enumerate(states) if state["zoom_x"] == 0x13000]
            if not indices or indices[0] != expected_zoom_update:
                raise ValueError(f"Unexpected delay resumption: {case['name']}")
            if states[1]["phase"] != 1 or states[1]["wait"] != delay or states[1]["cursor_word"] != 2:
                raise ValueError("Delay setup did not preserve its continuation")
            for i in range(2, expected_zoom_update):
                if states[i]["wait"] != delay - (i - 1) or states[i]["cursor_word"] != 2:
                    raise ValueError("Delay resumed early or decremented incorrectly")
        else:
            expected = [0x10000, *case["words"][1:-1:2], case["words"][-2]]
            if [state["zoom_x"] for state in states] != expected:
                raise ValueError("Consecutive zooms did not consume separate dispatcher updates")
        if states[-1]["phase"] != 101 or any(s["zoom_x"] != s["zoom_y"] for s in states):
            raise ValueError("Unexpected zoom/termination state")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ORIGINAL_EXE)
    parser.add_argument("--output", type=Path, default=PACKET)
    parser.add_argument("--check", action="store_true", help="Rerun native instructions and compare the stored packet")
    args = parser.parse_args()
    try:
        result = probe(args.exe)
        validate_observations(result)
        if args.check:
            if json.loads(args.output.read_text()) != result:
                raise ValueError("Stored native packet differs from current probe")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print(f"NATIVE_ANIMAL_SLICE_PASS cases={len(result['cases'])}")
        return 0
    except (ValueError, OSError, RuntimeError, ImportError) as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    raise SystemExit(main())
