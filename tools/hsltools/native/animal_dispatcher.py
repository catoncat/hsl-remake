"""The ANIMAL action dispatcher slice every animation probe executes: entry 0x401c20 (load the
program cursor, consume a 32-bit opcode, dispatch 0..33) to the shared presentation tail
0x4034c6, where the probes stop (docs/evidence_packets/static_reverse/animal_program_execution.md).
Shared by tools/hsl_native_animal_probe.py and the mobile_motion / priest_motion probes.
"""
from __future__ import annotations

ENTRY, STOP = 0x401C20, 0x4034C6
