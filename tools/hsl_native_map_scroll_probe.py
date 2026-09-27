#!/usr/bin/env python3
"""Execute original mouse-edge scroll request functions to full return.

This measures requested deltas, not final camera movement, map clamps, modal UI
gating or seconds per update. Optional analysis dependency: unicorn==2.1.4.
"""
from __future__ import annotations

import argparse
from itertools import product
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_EXE

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "docs/evidence_packets/static_reverse/original_mechanics_audit_scroll.json"


def request_delta(x: int, y: int, flags: int = 0) -> tuple[int, int]:
    """Literal strict inequalities and input bits from 0x43e4a0."""
    scale = 2 if flags & 0x600 else 1
    dx = (-12 if flags & 1 or x < 10 else 0) + (12 if flags & 2 or x > 630 else 0)
    dy = (-12 if flags & 4 or y < 10 else 0) + (12 if flags & 8 or y > 470 else 0)
    return dx * scale, dy * scale


def run(exe: Path) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
    from hsltools.native.image import EXE_SHA, image

    base, mapped = image(exe.read_bytes())
    cases = [(x, y, 0) for x, y in product((9, 10, 630, 631), (9, 10, 470, 471))]
    cases += [(320, 240, flag) for flag in (0, 1, 2, 4, 8, 15, 0x201, 0x404)]
    cases += [(9, 471, 0x200), (631, 9, 0x400)]
    results = []
    for x, y, flags in cases:
        for origin in ((0, 0), (96, 256)):
            machine = Uc(UC_ARCH_X86, UC_MODE_32)
            machine.mem_map(base, len(mapped))
            machine.mem_write(base, bytes(mapped))
            machine.mem_map(0x10000000, 0x10000)
            stack, stop = 0x1000FF00, 0x10000000
            def put(address, value):
                machine.mem_write(address, struct.pack("<I", value & 0xFFFFFFFF))
            def get(address):
                return struct.unpack("<i", machine.mem_read(address, 4))[0]
            for address, value in [(0x4C091C, origin[0]), (0x4C0920, origin[1]),
                                   (0x4C1A8C, origin[0]+x), (0x4C1A90, origin[1]+y),
                                   (0x4C6390, flags), (0x4C1B98, 100), (0x4C1B9C, -20)]:
                put(address, value)
            put(stack, stop)
            machine.reg_write(UC_X86_REG_ESP, stack)
            def guard(_machine, address, _size, _data):
                if not (0x43E4A0 <= address < 0x43E56C or 0x42DC50 <= address < 0x42DC73):
                    raise RuntimeError(f"Unexpected native scroll call {address:#x}")
            machine.hook_add(UC_HOOK_CODE, guard)
            machine.emu_start(0x43E4A0, stop, count=512)
            if machine.reg_read(UC_X86_REG_EIP) != stop or machine.reg_read(UC_X86_REG_ESP) != stack + 4:
                raise RuntimeError("Native scroll helper did not return within its instruction budget")
            delta = [get(0x4C1B98)-100, get(0x4C1B9C)+20]
            origin_after = [get(0x4C091C), get(0x4C0920)]
            if delta != list(request_delta(x, y, flags)) or origin_after != list(origin):
                raise ValueError("Native request differs from model or mutated camera origin")
            results.append({"viewport_pointer": [x, y], "camera_origin": list(origin),
                            "input_flags": flags, "request_before": [100, -20],
                            "request_after": [get(0x4C1B98), get(0x4C1B9C)],
                            "delta": delta, "returned": True, "camera_origin_unchanged": True})
    return {"schema": "hsl_native_scroll_request.v1", "evidence_tier": "static-derived",
            "exe_sha256": EXE_SHA, "entry": "0x43e4a0", "callee": "0x42dc50",
            "instruction_budget": 512, "cases": results,
            "instruction_anchors": [{"address": hex(address), "bytes": bytes(mapped[address-base:address-base+size]).hex()}
                                    for address, size in ((0x43E4A0, 204), (0x42DC50, 35))],
            "limits": ["Both request functions return normally; synthetic cursor, origin, flags and accumulated requests.",
                       "Strict x<10 / x>630 / y<10 / y>470 for the inspected 640x480 path.",
                       "Each triggered axis requests 12; mask 0x600 doubles the loop, physical key meaning not established here.",
                       "Does not consume pending scroll into camera position or prove map-edge clamp/modal gating/tick rate.",
                       "Does not prove every original game screen can be completed with the mouse alone.",
                       "Does not change the remake's keyboard-only camera pan input."]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ORIGINAL_EXE)
    parser.add_argument("--output", type=Path, default=PACKET)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = run(args.exe)
    if args.check:
        if json.loads(args.output.read_text()) != result:
            raise ValueError("Native scroll packet changed")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE_SCROLL_REQUEST_PASS cases={len(result['cases'])}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    try:
        raise SystemExit(main())
    except (ValueError, OSError, RuntimeError, ImportError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
