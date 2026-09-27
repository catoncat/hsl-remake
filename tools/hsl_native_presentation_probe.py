#!/usr/bin/env python3
"""Execute three bounded original presentation helpers, never the original game.

Optional analysis dependency: unicorn 2.x. Synthetic objects/calls are explicit;
no unknown callees are stubbed and no host input, window or process is used.
The resulting compact packet is a native-instruction oracle, NOT wall-clock or
whole-engine fidelity evidence. Runtime continues to use plain Godot code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
from pathlib import Path

from hsltools.assets.menu_layout import EXE_SHA
from hsltools.paths import ORIGINAL_EXE

ENTRIES = {"loop": (0x45E5A6, 0x45E5D9), "pingpong": (0x45E5D9, 0x45E642),
           "opening": (0x45E80D, 0x45E882)}


def probe(exe: Path) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP

    raw = exe.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXE_SHA:
        raise ValueError("Unsupported original executable")
    pe = struct.unpack_from("<I", raw, 60)[0]
    count = struct.unpack_from("<H", raw, pe + 6)[0]
    optional = struct.unpack_from("<H", raw, pe + 20)[0]
    base = struct.unpack_from("<I", raw, pe + 52)[0]
    size = struct.unpack_from("<I", raw, pe + 80)[0]
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, (size + 4095) & ~4095)
    for index in range(count):
        _, rva, length, offset = struct.unpack_from("<IIII", raw, pe + 24 + optional + 40 * index + 8)
        if length:
            machine.mem_write(base + rva, raw[offset:offset + length])
    machine.mem_map(0x10000000, 0x10000)
    machine.mem_map(0x20000000, 0x2000)
    stop, stack, obj = 0x10000000, 0x1000FF00, 0x20000000
    permitted = [0, 0]

    def guard(uc, address, instruction_size, _):
        if not permitted[0] <= address < permitted[1]:
            raise RuntimeError(f"Unexpected execution at {address:#x}; no dependency was stubbed")

    machine.hook_add(UC_HOOK_CODE, guard)

    def call(name, *arguments):
        permitted[:] = ENTRIES[name]
        machine.mem_write(stack, struct.pack("<" + "I" * (1 + len(arguments)), stop,
                                              *(int(value) & 0xFFFFFFFF for value in arguments)))
        machine.reg_write(UC_X86_REG_ESP, stack)
        machine.emu_start(permitted[0], stop, count=256)
        if machine.reg_read(UC_X86_REG_EIP) != stop:
            raise RuntimeError("Native helper exhausted its 256-instruction budget")

    frames = []
    for mode in ("loop", "pingpong"):
        for frame_count in (1, 2, 3, 5):
            machine.mem_write(obj, bytes(256))
            for offset, value in ((0x78, frame_count), (0x7A, frame_count), (0x7C, 6), (0x7E, 6)):
                machine.mem_write(obj + offset, struct.pack("<H", value))
            sequence = [0]
            for _ in range(84):
                call(mode, obj)
                sequence.append(struct.unpack("<h", machine.mem_read(obj + 0x30, 2))[0])
            frames.append({"mode": mode, "frames": frame_count, "initial_delay": 6,
                           "frame_by_update": sequence})
    opening = []
    for start, target in (((0, 0), (0, -72)), ((0, 0), (-58, -36)),
                          ((0, 0), (57, 37)), ((2, -2), (0, 0)), ((2, 4), (0, 0)),
                          ((-21, 11), (66, -72))):
        current = start
        positions = [list(current)]
        for _ in range(64):
            call("opening", *current, *target, 2, 8, obj, obj + 4)
            current = struct.unpack("<ii", machine.mem_read(obj, 8))
            positions.append(list(current))
            if current == target:
                break
        else:
            raise RuntimeError("Opening helper did not converge")
        opening.append({"start": list(start), "target": list(target), "positions": positions})
    return {"schema": "hsl_native_presentation_helpers.v1", "evidence_tier": "static-derived",
            "exe_sha256": EXE_SHA, "instruction_budget_per_call": 256,
            "helpers": {name: {"entry": hex(a), "end": hex(b),
                               "machine_code_sha256": hashlib.sha256(machine.mem_read(a, b - a)).hexdigest()}
                        for name, (a, b) in ENTRIES.items()},
            "frame_cases": frames, "opening_cases": opening,
            "limits": ["Synthetic input objects and explicit update calls, not live game event dispatch.",
                       "No assertion about calls/second, original menu availability, camera edges or complete rendering.",
                       "Only three original helpers executed; no mocked unknown functions."]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ORIGINAL_EXE)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = probe(args.exe)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print("NATIVE_PRESENTATION_PROBE_PASS frame_cases=%d opening_cases=%d" %
          (len(result["frame_cases"]), len(result["opening_cases"])))
