#!/usr/bin/env python3
"""Execute the original bounded four-attribute allowance helpers to full return.

0x439f70 asks 0x439f20 for at most five points. Both functions execute unchanged;
the roster, base attributes and caps are synthetic. No UI, random allocation,
derived stat refresh, original savegame or gameplay sequence is executed.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import ORIGINAL_EXE

ROOT = Path(__file__).resolve().parents[1]
PACKET = ROOT / "docs/evidence_packets/static_reverse/original_mechanics_audit_growth.json"
ATTRIBUTES = ("str", "dex", "mind", "con")


def allowance(base: list[int], caps: list[int], requested: int = 5) -> int:
    """Independent arithmetic model; intentionally do not clamp each deficit."""
    if len(base) != 4 or len(caps) != 4:
        raise ValueError("Exactly four base attributes and four caps are required")
    if any(type(x) is not int or not -100000 <= x <= 100000 for x in [*base, *caps, requested]):
        raise ValueError("Probe model only accepts bounded integer inputs")
    return max(0, min(requested, sum(cap - value for value, cap in zip(base, caps))))


def run(exe: Path) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX
    from hsltools.native.image import EXE_SHA, image

    image_base, mapped = image(exe.read_bytes())
    cases = [
        ("ordinary_capacity", [16, 16, 8, 12], [99, 99, 99, 99], 5),
        ("three_points_left", [16, 16, 8, 12], [17, 17, 9, 12], 5),
        ("one_point_left", [16, 16, 8, 12], [16, 16, 8, 13], 5),
        ("at_all_caps", [16, 16, 8, 12], [16, 16, 8, 12], 5),
        ("negative_total_capacity", [20, 20, 20, 20], [19, 19, 19, 19], 5),
        ("mixed_deficits_not_individually_clamped", [20, 20, 20, 20], [19, 22, 20, 20], 5),
        ("requested_zero", [16, 16, 8, 12], [99, 99, 99, 99], 0),
        ("requested_twelve", [16, 16, 8, 12], [99, 99, 99, 99], 12),
        ("requested_negative", [16, 16, 8, 12], [99, 99, 99, 99], -1),
    ]
    output = []
    for name, base, caps, requested in cases:
        for entry in (0x439F20, 0x439F70):
            machine = Uc(UC_ARCH_X86, UC_MODE_32)
            machine.mem_map(image_base, len(mapped))
            machine.mem_write(image_base, bytes(mapped))
            machine.mem_map(0x10000000, 0x10000)
            machine.mem_map(0x20000000, 0x10000)
            obj, roster, slot, stack, stop = 0x20000000, 0x20001000, 3, 0x1000FF00, 0x10000000
            actor = roster + slot * 0x1FC
            def put(address, value):
                machine.mem_write(address, struct.pack("<I", value & 0xFFFFFFFF))
            put(obj + 0xA4, slot)
            put(0x4C1BC8, roster)
            for i, value in enumerate(base):
                put(actor + 0x64 + i * 4, value)
            for i, value in enumerate(caps):
                put(actor + 0x74 + i * 4, value)
            before = bytes(machine.mem_read(obj, 0x10000))
            put(stack, stop)
            put(stack + 4, obj)
            put(stack + 8, requested)
            machine.reg_write(UC_X86_REG_ESP, stack)
            def guard(_machine, address, _size, _data):
                if not 0x439F20 <= address < 0x439F80:
                    raise RuntimeError(f"Unexplained native call {address:#x}")
            machine.hook_add(UC_HOOK_CODE, guard)
            machine.emu_start(entry, stop, count=256)
            if machine.reg_read(UC_X86_REG_EIP) != stop:
                raise RuntimeError("Native growth helper exceeded instruction budget")
            if machine.reg_read(UC_X86_REG_ESP) != stack + 4:
                raise RuntimeError("Native helper did not return with the expected stack")
            actual = machine.reg_read(UC_X86_REG_EAX)
            effective_request = 5 if entry == 0x439F70 else requested
            expected = allowance(base, caps, effective_request)
            if actual != expected or before != bytes(machine.mem_read(obj, 0x10000)):
                raise ValueError("Native allowance differs from model or mutated the input roster")
            output.append({"case": name, "entry": hex(entry), "base": base, "caps": caps,
                           "requested_argument": requested, "effective_request": effective_request,
                           "result": actual, "returned": True, "roster_unchanged": True})
    spans = [(0x439F20, 72, "sum four cap-base differences; clamp requested allowance to 0..remaining total"),
             (0x439F70, 16, "wrapper calls allowance helper with literal five"),
             (0x43A1CA, 46, "caller saves allowance and clears four allocation counters"),
             (0x43A224, 65, "same caller increments level, subtracts threshold EXP and clamps it at zero")]
    return {"schema": "hsl_native_growth_allowance.v1", "evidence_tier": "static-derived",
            "exe_sha256": EXE_SHA, "attributes": list(ATTRIBUTES),
            "field_layout": {"roster_base_global": "0x4c1bc8", "object_roster_index": "0xa4",
                             "roster_stride": 508, "base_offsets": [100, 104, 108, 112],
                             "cap_offsets": [116, 120, 124, 128]},
            "formula": "max(0, min(requested, sum(caps[i] - base[i] for i in range(4))))",
            "levelup_request": 5, "instruction_budget": 256, "cases": output,
            "instruction_anchors": [{"address": hex(address), "meaning": meaning,
                                     "bytes": bytes(mapped[address-image_base:address-image_base+size]).hex()}
                                    for address, size, meaning in spans],
            "limits": ["Full return of two small allowance helpers, not the entire level-up process.",
                       "Synthetic roster and caps, including invalid-state boundary fixtures; no native cap loader proof.",
                       "Five is a point budget across four base attributes, not five choices or a flat HP/attack/defense gain.",
                       "No free-point persistence, click allocation, class change, random allocation or derived-stat refresh proof.",
                       "This packet does not change the live remake three-point growth policy."]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ORIGINAL_EXE)
    parser.add_argument("--output", type=Path, default=PACKET)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = run(args.exe)
    if args.check:
        if json.loads(args.output.read_text()) != result:
            raise ValueError("Native growth packet changed")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE_GROWTH_ALLOWANCE_PASS cases={len(result['cases'])}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    try:
        raise SystemExit(main())
    except (ValueError, OSError, RuntimeError, ImportError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
