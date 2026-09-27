"""Byte-exact codec for the original save files (SAVES\\HSLBAT.SAV, SAVES\\HSLnn.SAV).

Static-derived from hsl01.exe (sha256 f0b5f835…): the writer 0x42e070, the reader
0x42e640, the block compressor 0x45b016 (LZW: 0x45a7b0 init, 0x45abd5 encode step,
0x45a8bc bit writer, 0x45aad7 add, 0x45ab7e lookup, 0x45aa43/0x45a925 prune on a full
dictionary), the decompressor 0x45b089 and the sliding-dword XOR checksum 0x42e040.
docs/evidence_packets/static_reverse/original_save_format.md is the field table.

The compressor is reproduced instruction for instruction (dictionary as a tree with
first-child / next-sibling links, free-list order, code-width growth, prune order) so the
sample round trip is byte-identical; nothing here is a generic LZW.
"""
from __future__ import annotations

import struct

CLEAR = 0x100          # escape code: followed by 1 (width += 1) or 2 (prune dictionary)
FIRST_CODE = 0x101     # first dictionary code
MAX_CODES = 0x2000     # codes 0x101 .. 0x1fff are dictionary entries
MAX_WIDTH = 13
RAW_COPY_BELOW = 10    # blocks shorter than this are stored verbatim (0x45b016 / 0x45b089)


class _BitWriter:
    """0x45a8bc: codes are emitted LSB first into bytes; 0x45a881 stops at `limit` bytes."""

    def __init__(self, limit: int) -> None:
        self.limit = limit
        self.out = bytearray()
        self.acc = 0
        self.nbits = 0
        self.overflow = False

    def _byte(self, value: int) -> None:
        if self.limit < 0 or len(self.out) < self.limit:
            self.out.append(value & 0xFF)
        else:
            self.overflow = True

    def put(self, code: int, width: int) -> None:
        for _ in range(width):
            if code & 1:
                self.acc |= 1 << self.nbits
            code >>= 1
            self.nbits += 1
            if self.nbits >= 8:
                self._byte(self.acc)
                self.acc = 0
                self.nbits = 0

    def flush(self) -> None:
        if self.nbits:
            self._byte(self.acc)


class _Encoder:
    """The global-state compressor of 0x45a7b0 .. 0x45abd5 as one object."""

    def __init__(self, limit: int) -> None:
        self.child = [-1] * (MAX_CODES + 1)     # 0x47d46e: first child
        self.sibling = [-1] * (MAX_CODES + 1)   # 0x47d472: next sibling
        self.value = [0] * (MAX_CODES + 1)      # 0x47d476: byte of this node
        for code in range(0x100):
            self.value[code] = code
        # 0x47966c: the code allocated next is free[next_code - 0x101]; the last slot (0x2000)
        # is only ever read by the width test and never allocated.
        self.free = list(range(FIRST_CODE, MAX_CODES + 1))
        self.next_code = FIRST_CODE   # 0x47965c
        self.full = -1                # 0x479648: 1 once 0x2000 codes are allocated
        self.width = 9                # 0x479658
        self.max_code = 0x1FF         # 0x479664
        self.current = -1             # 0x479660
        self.started = False          # 0x479650 == 1 before the first byte
        self.bits = _BitWriter(limit)

    # 0x45ab7e
    def find(self, parent: int, byte: int) -> int:
        node = self.child[parent]
        while node != -1:
            if self.value[node] == byte:
                return node
            node = self.sibling[node]
        return -1

    # 0x45aad7
    def add(self, parent: int, byte: int) -> None:
        if self.next_code >= MAX_CODES:
            return
        code = self.free[self.next_code - FIRST_CODE]
        self.next_code += 1
        self.child[code] = -1
        self.sibling[code] = -1
        self.value[code] = byte
        node = self.child[parent]
        if node == -1:
            self.child[parent] = code
        else:
            while self.sibling[node] != -1:
                node = self.sibling[node]
            self.sibling[node] = code
        if self.next_code > 0x1FFF:
            self.full = 1

    # 0x45a925: unlink the leaf children below `node` (recursively into non-leaf children)
    def prune(self, node: int, freed: bytearray) -> None:
        child = self.child[node]
        while child != -1 and self.child[child] == -1:
            nxt = self.sibling[child]
            self.sibling[child] = -1
            self.child[node] = nxt
            freed[child] = 1
            child = self.child[node]
        if child == -1:
            return
        self.prune(child, freed)
        prev = child
        cur = self.sibling[child]
        while cur != -1:
            if self.child[cur] == -1:
                nxt = self.sibling[cur]
                self.sibling[cur] = -1
                self.sibling[prev] = nxt
                freed[cur] = 1
                cur = self.sibling[prev]
            else:
                self.prune(cur, freed)
                prev = cur
                cur = self.sibling[prev]

    # 0x45aa43
    def rebuild(self) -> None:
        freed = bytearray(MAX_CODES)
        for root in range(0x100):
            self.prune(root, freed)
        self.next_code = MAX_CODES
        for code in range(0x1FFF, 0x100, -1):
            if freed[code]:
                self.next_code -= 1
                self.free[self.next_code - FIRST_CODE] = code
        if self.next_code < MAX_CODES:
            self.full = -1

    # 0x45abd5
    def step(self, byte: int) -> None:
        if not self.started:
            self.started = True
            self.current = byte
            return
        if self.full == 1:
            self.bits.put(self.current, self.width)
            self.bits.put(CLEAR, self.width)
            self.bits.put(2, self.width)
            self.rebuild()
            self.add(self.current, byte)
            self.current = byte
            return
        node = self.find(self.current, byte)
        if node != -1:
            self.current = node
            return
        self.bits.put(self.current, self.width)
        self.add(self.current, byte)
        self.current = byte
        if self.free[self.next_code - FIRST_CODE] > self.max_code and self.width < MAX_WIDTH:
            self.bits.put(CLEAR, self.width)
            self.bits.put(1, self.width)
            self.width += 1
            self.max_code = (1 << self.width) - 1

    def finish(self) -> bytes:
        if self.started:
            self.bits.put(self.current, self.width)
        self.bits.flush()
        if self.bits.overflow:
            raise ValueError('compressed block exceeds the writer limit (0x45a881 would report length 0)')
        return bytes(self.bits.out)


def lzw_encode(data: bytes, limit: int = -1) -> bytes:
    """0x45b016(dst, src, len, limit): verbatim copy under 10 bytes, otherwise LZW."""
    if len(data) < RAW_COPY_BELOW:
        return bytes(data)
    encoder = _Encoder(limit)
    for byte in data:
        encoder.step(byte)
    return encoder.finish()


class _BitReader:
    def __init__(self, data: bytes) -> None:
        self.data = data
        self.pos = 0
        self.acc = 0
        self.nbits = 0

    def get(self, width: int) -> int:
        value = 0
        for bit in range(width):
            if self.nbits == 0:
                if self.pos >= len(self.data):
                    return -1
                self.acc = self.data[self.pos]
                self.pos += 1
                self.nbits = 8
            value |= (self.acc & 1) << bit
            self.acc >>= 1
            self.nbits -= 1
        return value


def lzw_decode(data: bytes, out_size: int) -> bytes:
    """0x45b089(dst, src, len, out_limit): the reader of lzw_encode's stream (prefix table,
    0x45ae3c leaf prune on CLEAR 2). out_size is the decompressed size the caller expects."""
    if len(data) < RAW_COPY_BELOW:
        return bytes(data)
    parent = [-1] * (MAX_CODES + 1)
    last = [0] * (MAX_CODES + 1)
    children = [0] * (MAX_CODES + 1)
    for code in range(0x100):
        last[code] = code
    free = list(range(FIRST_CODE, MAX_CODES + 1))
    next_code = FIRST_CODE
    width = 9
    reader = _BitReader(data)
    out = bytearray()

    def string_of(code: int) -> bytes:
        chars = []
        while code > 0xFF:
            chars.append(last[code])
            code = parent[code]
        chars.append(last[code])
        return bytes(reversed(chars))

    def add(prev: int, byte: int) -> None:
        nonlocal next_code
        if next_code >= MAX_CODES:
            return
        code = free[next_code - FIRST_CODE]
        next_code += 1
        last[code] = byte
        parent[code] = prev
        children[prev] += 1

    def prune() -> None:
        nonlocal next_code
        leaves = [code for code in range(FIRST_CODE, MAX_CODES + 1) if children[code] == 0]
        next_code = MAX_CODES
        for code in reversed(leaves):
            if parent[code] != -1:
                children[parent[code]] -= 1
            parent[code] = -1
            last[code] = 0
            children[code] = 0
            next_code -= 1
            free[next_code - FIRST_CODE] = code

    prev = reader.get(width)
    if prev == -1:
        return bytes(out)
    out.append(prev)
    code = reader.get(width)
    while code != -1 and len(out) < out_size:
        if code == CLEAR:
            escape = reader.get(width)
            if escape == 1:
                width += 1
            elif escape == 2:
                prune()
            else:
                raise ValueError(f'bad LZW escape {escape}')
        else:
            if code > 0x1FFF:
                raise ValueError(f'bad LZW code {code:#x}')
            if code >= FIRST_CODE and parent[code] == -1:
                text = string_of(prev) + bytes([string_of(prev)[0]])
            else:
                text = string_of(code)
            out.extend(text)
            add(prev, text[0])
            prev = code
        code = reader.get(width)
    return bytes(out[:out_size])


def checksum(data: bytes) -> int:
    """0x42e040: XOR of every little-endian dword at each byte offset 0 .. len-4."""
    value = 0
    for offset in range(len(data) - 3):
        value ^= struct.unpack_from('<I', data, offset)[0]
    return value & 0xFFFFFFFF
