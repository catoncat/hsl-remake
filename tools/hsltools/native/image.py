"""The documented hsl01.exe image: SHA-256 identity and PE section mapping.

image(raw) maps the sections of the original executable to their virtual addresses so a
probe can load them into an emulator (base, mapped). Every probe shares this one
loader; the SHA gate refuses any other EXE. Body moved verbatim from
hsl_native_animal_probe.py.
"""
from __future__ import annotations

import hashlib
import struct

EXE_SHA = "f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7"


def image(raw: bytes) -> tuple[int, bytearray]:
    if hashlib.sha256(raw).hexdigest() != EXE_SHA:
        raise ValueError("Unsupported EXE: expected the documented hsl01.exe SHA256")
    pe = struct.unpack_from("<I", raw, 60)[0]
    count = struct.unpack_from("<H", raw, pe + 6)[0]
    optional = struct.unpack_from("<H", raw, pe + 20)[0]
    base = struct.unpack_from("<I", raw, pe + 52)[0]
    size = struct.unpack_from("<I", raw, pe + 80)[0]
    mapped = bytearray((size + 4095) & ~4095)
    for index in range(count):
        _, rva, length, offset = struct.unpack_from("<IIII", raw, pe + 24 + optional + 40 * index + 8)
        if length:
            mapped[rva:rva + length] = raw[offset:offset + length]
    return base, mapped
