"""Emulator machine factory for the bounded native probes.

machine_for(base, mapped) maps the loaded EXE image into a fresh 32-bit unicorn machine
with the scratch window the probes use at 0x10000000. Optional analysis dependency:
unicorn (imported lazily). Body moved verbatim from the former hsl_native_experience_probe.py.
"""
from __future__ import annotations


def machine_for(base: int, mapped: bytearray):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped)); machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x20000)
    return machine
