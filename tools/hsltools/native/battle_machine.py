"""Whole-image hsl01.exe machine: engine init, text tables, level loader and the original
battle-save reader, then the original frame body — for battle-state oracles.

Unlike the bounded probes (hsltools.native.machine) this maps the whole documented EXE into
one unicorn machine and runs the game's own initialisation and frame code. The only
non-original code is the shim layer below; everything it does is listed in SHIMS so a
packet can carry it. Optional dependency: unicorn (imported lazily; run with
`uv run --with unicorn==2.1.4`).

Shims:
1. Win32 imports → an allow-list: GetTickCount／timeGetTime return a counter that grows by
   one per call, FindFirstFileA returns INVALID_HANDLE_VALUE, PeekMessageA and the key-state
   calls return 0. Any other import stops the run (stop_reason names it).
2. CRT heap: malloc 0x457b70 → bump allocator, free 0x457c20 → no-op, _msize 0x46ea4e,
   realloc 0x46eaeb.
3. The game's own file layer (0x46c830／0x46c880 open, 0x46cab0 read, 0x46cba0 seek,
   0x46cb70 size, 0x46c970 close) → in-memory files: SAVES\\HSLBAT.SAV is the given save,
   every other path is read from hsl.pak next to the EXE.
4. Graphics: the shape-cache loaders 0x4601a2／0x460058 return 0 (no shape is decoded),
   0x45fc01 (resource name → id) hands out sequential ids, 0x446480 (missing text) returns 0.
   Frames additionally skip the walker's sprite draw pass (0x45f724 → 0x45f75e), the shape
   draws 0x4607f9 and 0x460799 and text 0x460884, and stub the presentation blit 0x42d280 — the stub
   leaves the frame-presented flag [0x4c1b1c] = 1, as 0x42d280 does on every presented frame
   (0x42d2b3／0x42d359; it clears it at 0x42d282 first). Rule paths read that flag: the
   camera wait 0x43bf30 in a 0x80000000 mode only reports arrival once it is set (0x43bfe0;
   callers 0x442c55 and the cast flow 0x44301e), the shake at 0x4176af／0x41d528／0x421766.
   The blit 0x461479 runs original (stubbing it changed nothing; see enemy_turn ablations).
   0x460799 is 0x4607f9's sibling (blit parameters into 0x4bbb9a.., shape [0x4abf28 + id*4],
   else 'Shape not loaded' 0x46e100(3, id)); with no shape decoded it can only fatal. Its seven
   callers (0x424ecd 0x430346 0x436ae8 0x436de2 0x43da5c 0x4458aa 0x4458cd) are object draws;
   level 3 reaches 0x436ae8 in its first NPC attack. The only other 'Shape not loaded' site,
   0x45f78f, is inside the skipped walker draw pass.
5. The fatal-error box 0x45b29e stops the run.

New-level branch (enter_level): 0x42da60(level) with the load flag [0x4c1ae4] clear, as a
level is entered in play (resets, level loader, EVEF instances, the opening scripts), run
through the original frame loop 0x42dbf0 itself; LEVEL_SHIMS lists what differs from WinMain.
A run halted from a hook is snapshotted with its registers and stack and resumed later.

Load path (WinMain 0x42f1ad order): engine init 0x46d14c, the WinMain buffers
0x42f34c..0x42f4cf, the 12 text-table loaders, GLOBAL.OBS through 0x45dc5c, the level-start
resets 0x42c640／0x407260／0x45fb5c, the level loader 0x42ce10(level), 0x45e224, and the save
reader 0x42e640(0, 0, 1). The loaded state is cached as a pickle under ignored/ (keyed by the
EXE SHA, the save SHA, the level and CACHE_VERSION) and rebuilt when missing.
"""
from __future__ import annotations

import hashlib
import pickle
import struct
from collections import Counter
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT

CACHE_DIR = ROOT / 'ignored/native_cache/battle_machine'
CACHE_VERSION = 1
M32 = 0xffffffff
SCRATCH, SCRATCH_SIZE = 0x10000000, 0x01000000
SENTINEL = 0x10000000
IMPORT_STUBS = 0x10001000
STACK_TOP = 0x10200000 - 0x100
PATH_BUFFER = 0x10300000
STRING_BUFFER = 0x10300400
HEAP, HEAP_SIZE = 0x20000000, 0x10000000
TICK_START = 1000
STDCALL_ARGS = {'GetTickCount': 0, 'PeekMessageA': 5, 'GetKeyState': 1, 'GetAsyncKeyState': 1, 'timeGetTime': 0,
                'TranslateMessage': 1, 'DispatchMessageA': 1, 'Sleep': 1, 'GetKeyboardState': 1}
# WinMain 0x42f34c..0x42f4cf: work buffers allocated before the table loaders.
WINMAIN_BUFFERS = ((0x4c1b44, 0x28a4), (0x4c1b48, 0x190), (0x4c1b4c, 0x190), (0x4c1b78, 0x2800),
                   (0x4c1b7c, 0x1400), (0x4c1b80, 0x2800), (0x4c1b88, 0x1400))
TABLE_LOADERS = ((0x446800, 'DATA\\SHAPEDEF.TXT'), (0x446d30, 'DATA\\ANIMAL.TXT'), (0x447260, 'DATA\\EFFECTS.TXT'),
                 (0x447440, 'DATA\\OBJCOMD.TXT'), (0x447720, 'DATA\\RESOURCE.TXT'), (0x4477c0, 'DATA\\ITEM.TXT'),
                 (0x44b980, 'DATA\\PLAYERS.TXT'), (0x44d300, 'DATA\\RANGE.TXT'), (0x44d4b0, 'DATA\\SPECIAL.TXT'),
                 (0x44d910, 'DATA\\MAGIC.TXT'), (0x44de20, 'DATA\\TRACK.TXT'), (0x44e110, 'DATA\\TOWNDEF.TXT'))
FRAME_BODY = 0x42d600
FRAME_STUBS = ((0x4607f9, 'draw shape 0x4607f9'), (0x460799, 'draw shape 0x460799'), (0x460884, 'draw text 0x460884'),
               (0x42d280, 'present 0x42d280'))
PRESENT, PRESENTED = 0x42d280, 0x4c1b1c   # 0x42d280 clears [0x4c1b1c] on entry and sets it to 1 once the frame is shown
DRAW_SKIP = (0x45f724, 0x45f75e)
RAND_INNER_RETURNS = (0x458c96, 0x458ca7)   # 0x458c80 rand(n) calls the raw 0x458c10 from 0x458c91／0x458ca2
# The new-level branch (hsltools.probes._enemy_level): 0x42da60(level) with the load flag clear.
LEVEL_START, LEVEL_ENTRY, LEVEL_LOOP = 0x42da60, 0x42dbf0, 0x42dbf5   # 0x42dbf0 `mov esi, 0x38000000`, loop head 0x42dbf5
FRAME_FN, FIRST_FRAME_FN = 0x4c1b24, 0x42d7a0       # WinMain 0x42f1cc: [0x4c1b24] = 0x42d7a0 (installs 0x42d600)
LEVEL_NUMBER, LOAD_FLAG, START_MOVIE = 0x4c1bac, 0x4c1ae4, 0x42def0
MOUSE_BUTTONS = 0x4c2344      # WndProc 0x458530: bit0 left, bit1 right; 0x415910 folds it into [0x4c6398]
REGISTERS = ('EAX', 'EBX', 'ECX', 'EDX', 'ESI', 'EDI', 'EBP', 'ESP', 'EIP', 'EFLAGS', 'FPCW')
SHIMS = [
    'imports: GetTickCount/timeGetTime +1 per call; FindFirstFileA -> INVALID_HANDLE_VALUE; PeekMessageA/key state -> 0; any other import stops',
    'heap: malloc 0x457b70 bump, free 0x457c20 no-op, _msize 0x46ea4e, realloc 0x46eaeb',
    'files: 0x46c830/0x46c880/0x46cab0/0x46cba0/0x46cb70/0x46c970 -> in-memory (SAVES\\HSLBAT.SAV = the given save, rest from hsl.pak)',
    'graphics: 0x4601a2/0x460058 shape loaders -> 0, 0x45fc01 resource id -> sequential, 0x446480 missing text -> 0',
    'frame: walker draw pass 0x45f724 -> 0x45f75e; 0x4607f9/0x460799 shape draw, 0x460884 text -> return 0; 0x42d280 present -> [0x4c1b1c] = 1 (frame presented), return 0',
    'fatal box 0x45b29e stops the run',
]
# Extra shims of the new-level branch (enter_level; hsltools.probes._enemy_level carries them).
LEVEL_SHIMS = [
    'level start: [0x4c1bac] = level, [0x4c1ae4] = 0 (new level, not a save load), [0x4c1b24] = 0x42d7a0 (WinMain 0x42f1cc); opening movie 0x42def0 -> return 0',
    'frame shims installed at the loop entry 0x42dbf0 (not before 0x42da60)',
]


def pe_imports(raw: bytes) -> list[tuple[int, str, str]]:
    """(IAT slot VA, dll, name) for every import of the EXE."""
    pe = struct.unpack_from('<I', raw, 60)[0]
    base = struct.unpack_from('<I', raw, pe + 52)[0]
    import_rva = struct.unpack_from('<I', raw, pe + 24 + 104)[0]
    count = struct.unpack_from('<H', raw, pe + 6)[0]
    optional = struct.unpack_from('<H', raw, pe + 20)[0]
    sections = [struct.unpack_from('<IIII', raw, pe + 24 + optional + 40 * i + 8) for i in range(count)]

    def offset(rva: int) -> int:
        for vsize, va, rsize, raw_offset in sections:
            if va <= rva < va + max(vsize, rsize):
                return rva - va + raw_offset
        raise ValueError(hex(rva))

    out, cursor = [], offset(import_rva)
    while True:
        original_thunk, _, _, name_rva, first_thunk = struct.unpack_from('<IIIII', raw, cursor)
        if not name_rva:
            break
        dll = raw[offset(name_rva):raw.index(b'\0', offset(name_rva))].decode()
        thunk, slot = offset(original_thunk or first_thunk), first_thunk
        while (value := struct.unpack_from('<I', raw, thunk)[0]):
            name = f'#{value & 0xffff}' if value & 0x80000000 else raw[offset(value) + 2:raw.index(b'\0', offset(value) + 2)].decode()
            out.append((base + slot, dll, name))
            thunk += 4
            slot += 4
        cursor += 20
    return out


class Pak:
    """hsl.pak records by upper-case relative path (DATA\\X.TXT)."""

    def __init__(self, path: Path) -> None:
        from hsltools.sources.pak import read_decoded_paks_package
        self.path = path
        self.records = {r['name'].upper().replace('/', '\\')[3:]: r
                        for r in read_decoded_paks_package(path, path.parent)['records']}

    def read(self, rel: str) -> bytes | None:
        from hsltools.sources.pak import read_paks_record_bytes
        for candidate in (rel, 'DATA\\' + rel.split('\\')[-1]):
            if candidate in self.records:
                return read_paks_record_bytes(self.path, self.records[candidate])
        return None


class BattleMachine:
    """One unicorn machine holding the whole EXE image plus the shim layer."""

    def __init__(self, exe: Path, save: bytes) -> None:
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE, UC_HOOK_MEM_UNMAPPED
        from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP, UC_X86_REG_EIP
        self._EAX, self._ESP, self._EIP, self._HOOK_CODE = UC_X86_REG_EAX, UC_X86_REG_ESP, UC_X86_REG_EIP, UC_HOOK_CODE
        raw = exe.read_bytes()
        base, mapped = image(raw)
        self.exe, self.save = exe, save
        self.mu = mu = Uc(UC_ARCH_X86, UC_MODE_32)
        mu.mem_map(base, len(mapped))
        mu.mem_write(base, bytes(mapped))
        self.image_range = (base, len(mapped))
        mu.mem_map(SCRATCH, SCRATCH_SIZE)
        mu.mem_map(HEAP, HEAP_SIZE)
        self.heap = HEAP
        self.tick = TICK_START
        self.sizes: dict[int, int] = {}
        self.resources: dict[str, int] = {}
        self.imports_hit: Counter = Counter()
        self.stub_hits: Counter = Counter()
        self.undefined: Counter = Counter()
        self.stop_reason: str | None = None
        self.halted: str | None = None
        self.open_files: dict[int, list] = {}
        self._pak: Pak | None = None
        self.names: dict[int, tuple[str, str]] = {}
        for index, (slot, dll, name) in enumerate(pe_imports(raw)):
            stub = IMPORT_STUBS + 16 * index
            self.names[stub] = (dll, name)
            mu.mem_write(stub, b'\xc3')
            self.put(slot, stub)
        mu.hook_add(UC_HOOK_CODE, self._import, begin=IMPORT_STUBS, end=IMPORT_STUBS + 16 * len(self.names))
        mu.hook_add(UC_HOOK_MEM_UNMAPPED, self._fault)
        self.hook(0x457b70, self._malloc)
        self.hook(0x457c20, lambda: self.ret(0))
        self.hook(0x46ea4e, lambda: self.ret(self.sizes.get(self.arg(0), 0)))
        self.hook(0x46eaeb, self._realloc)
        for at, fn in ((0x46c830, self._open), (0x46c880, self._open), (0x46cab0, self._read), (0x46cba0, self._seek),
                       (0x46cb70, self._size), (0x46c970, self._close)):
            self.hook(at, fn)
        self.hook(0x45b29e, self._fatal)
        self.hook(0x45fc01, lambda: self.ret(self.resources.setdefault(self.cstr(self.arg(0)), len(self.resources) + 1)))
        self.hook(0x446480, self._undefined)
        self.stub(0x4601a2, 0, 'shape load 0x4601a2')
        self.stub(0x460058, 0, 'shape load 0x460058')
        self.put(0x4c1b84, PATH_BUFFER)
        mu.mem_write(0x4c2298, b'C:\\HSL\\\0')

    # ---- memory
    def get(self, at: int) -> int: return struct.unpack('<I', self.mu.mem_read(at, 4))[0]
    def geti(self, at: int) -> int: return struct.unpack('<i', self.mu.mem_read(at, 4))[0]
    def get16(self, at: int) -> int: return struct.unpack('<H', self.mu.mem_read(at, 2))[0]
    def put(self, at: int, value: int) -> None: self.mu.mem_write(at, struct.pack('<I', value & M32))
    def put16(self, at: int, value: int) -> None: self.mu.mem_write(at, struct.pack('<H', value & 0xffff))
    def cstr(self, at: int) -> str: return bytes(self.mu.mem_read(at, 260)).split(b'\0')[0].decode('cp950', 'replace')
    def esp(self) -> int: return self.mu.reg_read(self._ESP)
    def eax(self) -> int: return self.mu.reg_read(self._EAX)
    def arg(self, index: int) -> int: return self.get(self.esp() + 4 * (index + 1))
    def return_address(self) -> int: return self.get(self.esp())

    def alloc(self, size: int) -> int:
        at = self.heap
        self.heap += (max(size, 1) + 15) & ~15
        if self.heap > HEAP + HEAP_SIZE:
            raise MemoryError('bump heap exhausted')
        return at

    # ---- hooks
    def hook(self, at: int, fn) -> int:
        """fn() before the instruction at `at` runs. unicorn 2 decides at translation time whether a
        block calls the code hooks, so a block translated before this hook existed would skip it: the
        cached translation of `at` is dropped (ctl_remove_cache) and re-made with the hook."""
        handle = self.mu.hook_add(self._HOOK_CODE, lambda mu, address, size, data: fn(), begin=at, end=at)
        self.mu.ctl_remove_cache(at, at + 1)
        return handle

    def unhook(self, handle: int) -> None:
        self.mu.hook_del(handle)

    def stub(self, at: int, value: int = 0, label: str = '') -> int:
        """Replace a cdecl function by `return value` (counted in stub_hits)."""
        def fn():
            self.stub_hits[label or hex(at)] += 1
            self.ret(value)
        return self.hook(at, fn)

    def jump(self, at: int, target: int) -> int:
        return self.hook(at, lambda: self.mu.reg_write(self._EIP, target))

    def ret(self, value: int, stdcall_args: int = 0) -> None:
        esp = self.esp()
        back = self.get(esp)
        self.mu.reg_write(self._EAX, value & M32)
        self.mu.reg_write(self._ESP, esp + 4 + 4 * stdcall_args)
        self.mu.reg_write(self._EIP, back)

    def _import(self, mu, address, size, data):
        dll, name = self.names[address]
        caller = self.return_address()
        self.imports_hit[f'{name}@{caller:#x}'] += 1
        if name in ('GetTickCount', 'timeGetTime'):
            self.tick += 1
            return self.ret(self.tick)
        if name == 'FindFirstFileA':
            return self.ret(M32, 2)
        if name in STDCALL_ARGS:
            return self.ret(0, STDCALL_ARGS[name])
        self.stop_reason = f'import {dll}!{name} called from {caller:#x}'
        mu.emu_stop()

    def _malloc(self):
        size = self.arg(0)
        at = self.alloc(size)
        self.sizes[at] = size
        self.mu.mem_write(at, bytes(size))
        self.ret(at)

    def _realloc(self):
        old, size = self.arg(0), self.arg(1)
        at = self.alloc(size)
        self.sizes[at] = size
        if old:
            self.mu.mem_write(at, bytes(self.mu.mem_read(old, min(size, self.sizes.get(old, size)))))
        self.ret(at)

    def _resolve(self, path: str) -> bytes | None:
        upper = path.upper().replace('/', '\\')
        if upper.endswith('SAVES\\HSLBAT.SAV'):
            return self.save
        if self._pak is None:
            self._pak = Pak(self.exe.with_name('hsl.pak'))
        rel = upper[len('C:\\HSL\\'):] if upper.startswith('C:\\HSL\\') else upper.lstrip('@:\\')
        return self._pak.read(rel)

    def _open(self):
        blob = self._resolve(self.cstr(self.arg(0)))
        if blob is None:
            return self.ret(M32)
        handle = 0x100 + len(self.open_files)
        self.open_files[handle] = [blob, 0]
        self.ret(handle)

    def _read(self):
        handle, buffer, count = self.arg(0), self.arg(1), self.arg(2)
        entry = self.open_files[handle]
        chunk = entry[0][entry[1]:entry[1] + count]
        self.mu.mem_write(buffer, chunk)
        entry[1] += len(chunk)
        self.ret(len(chunk))

    def _seek(self):
        handle, offset, whence = self.arg(0), self.geti(self.esp() + 8), self.arg(2)
        entry = self.open_files[handle]
        entry[1] = (offset, entry[1] + offset, len(entry[0]) + offset)[whence]
        self.ret(entry[1])

    def _size(self):
        self.ret(len(self.open_files[self.arg(0)][0]))

    def _close(self):
        self.open_files.pop(self.arg(0), None)
        self.ret(0)

    def _undefined(self):
        self.undefined[self.cstr(self.arg(0)) if self.arg(0) else '?'] += 1
        self.ret(0)

    def _fatal(self):
        self.stop_reason = f'fatal 0x45b29e from {self.return_address():#x}: {self.cstr(self.arg(0))!r}'
        self.mu.emu_stop()

    def _fault(self, mu, access, address, size, value, data):
        self.stop_reason = f'unmapped access {address:#x} at eip {mu.reg_read(self._EIP):#x}'
        return False

    def call(self, fn: int, *args: int, budget: int = 400_000_000) -> int:
        """Run the cdecl function fn(*args) until it returns to the sentinel (or a hook halts)."""
        self.mu.mem_write(STACK_TOP, struct.pack('<' + 'I' * (len(args) + 1), SENTINEL, *args))
        self.mu.reg_write(self._ESP, STACK_TOP)
        self._run(fn, budget)
        return self.eax()

    def resume(self, budget: int = 0) -> int:
        """Continue a halted call from the current EIP until it returns to the sentinel or halts again."""
        self._run(self.mu.reg_read(self._EIP), budget)
        return self.eax()

    def halt(self, reason: str) -> None:
        """Stop the running call from a hook, resumable (halted names why; not an error)."""
        self.halted = reason
        self.mu.emu_stop()

    def _run(self, begin: int, budget: int) -> None:
        from unicorn import UcError
        self.stop_reason = None
        self.halted = None
        try:
            self.mu.emu_start(begin, SENTINEL, count=budget)
        except UcError as error:
            self.stop_reason = self.stop_reason or f'UcError {error} at {self.mu.reg_read(self._EIP):#x}'
        if self.stop_reason is None and self.halted is None and self.mu.reg_read(self._EIP) != SENTINEL:
            self.stop_reason = f'instruction budget at {self.mu.reg_read(self._EIP):#x}'

    def call_checked(self, fn: int, *args: int) -> int:
        result = self.call(fn, *args)
        if self.stop_reason:
            raise RuntimeError(f'{fn:#x}: {self.stop_reason}')
        return result

    def joined_path(self, rel: str) -> int:
        self.mu.mem_write(STRING_BUFFER, rel.encode() + b'\0')
        return self.call_checked(0x42cd10, STRING_BUFFER)

    # ---- load path
    def boot_engine(self) -> None:
        """WinMain 0x42f1ad up to the first level: engine init, work buffers, text tables, GLOBAL.OBS."""
        self.call_checked(0x46d14c, 0x1e8480, 0x477980, 0x109a000, 0, 1000, 0x477c2c)   # WinMain engine init
        for at, size in WINMAIN_BUFFERS:
            self.put(at, self.alloc(size))
        for at, rel in TABLE_LOADERS:
            self.call_checked(at, self.joined_path(rel))
        self.call_checked(0x45dc5c, self.joined_path('DATA\\GLOBAL.OBS'), 0, 0x42cdd0)

    def boot_and_load(self, level: int) -> None:
        self.boot_engine()
        # Level start 0x42da60 with the load flag: resets, level loader, then 0x42ebe0(1) -> 0x42e640(0, 0, 1).
        self.put(0x4c1bb8, level)
        self.put(0x4c1bac, level)
        for fn in (0x42c640, 0x407260, 0x45fb5c):
            self.call_checked(fn)
        self.call_checked(0x42ce10, level)
        for pointer, size in WINMAIN_BUFFERS[:3]:
            self.mu.mem_write(self.get(pointer), bytes(size))
        self.call_checked(0x45e224)
        if self.call_checked(0x42e640, 0, 0, 1) != 1:
            raise RuntimeError('save reader 0x42e640 did not return 1')

    def enter_level(self, level: int, on_frame, keep: tuple[int, ...] = ()) -> None:
        """The original new-level branch 0x42da60(level) (load flag [0x4c1ae4] = 0: resets, level
        loader 0x42ce10, EVEF instances 0x46be17(0, 0x42bd50), 0x42dca0(2) ...) into its own frame
        loop 0x42dbf0; on_frame() runs at every loop head 0x42dbf5 (before `call [0x4c1b24]`) and
        ends the run with halt(). [0x4c1b24] = 0x42d7a0 as WinMain sets it (0x42f1cc); the level-51
        opening movie 0x42def0 is stubbed. The frame shims go in when the loop is entered
        (0x42dbf0): installed before 0x42da60 they also stub the opening's own screen set-up and
        the level never gets past its first frames. Resumable with resume()."""
        installed = []

        def at_loop():
            if not installed:
                self.install_frame_stubs(keep)
                installed.append(True)
        self.put(LEVEL_NUMBER, level)
        self.put(LOAD_FLAG, 0)
        self.put(FRAME_FN, FIRST_FRAME_FN)
        self.stub(START_MOVIE, 0, 'opening movie 0x42def0')
        self.hook(LEVEL_ENTRY, at_loop)
        self.hook(LEVEL_LOOP, on_frame)
        self.call(LEVEL_START, level, budget=0)

    def call_nested(self, fn: int, *args: int, budget: int = 50_000_000) -> int:
        """Run fn(*args) on a stack below the current one while a call is halted, then put every
        register (and halted) back so resume() continues the halted call unchanged."""
        from unicorn import x86_const
        saved = {name: self.mu.reg_read(getattr(x86_const, f'UC_X86_REG_{name}')) for name in REGISTERS}
        halted = self.halted
        top = saved['ESP'] if SCRATCH < saved['ESP'] <= STACK_TOP + 0x100 else STACK_TOP   # no call halted: the scratch stack
        esp = (top - 0x1000) & ~0xf
        self.mu.mem_write(esp, struct.pack('<' + 'I' * (len(args) + 1), SENTINEL, *args))
        self.mu.reg_write(self._ESP, esp)
        self._run(fn, budget)
        result, reason = self.eax(), self.stop_reason
        for name, value in saved.items():
            self.mu.reg_write(getattr(x86_const, f'UC_X86_REG_{name}'), value)
        self.halted, self.stop_reason = halted, None
        if reason:
            raise RuntimeError(f'{fn:#x} (nested): {reason}')
        return result

    def snapshot(self, registers: bool = False) -> dict:
        """Image, heap and allocator state; with registers also the CPU registers and the live
        stack, so a run halted inside a call can be restored and resumed."""
        base, size = self.image_range
        state = dict(mem=[(base, bytes(self.mu.mem_read(base, size))), (HEAP, bytes(self.mu.mem_read(HEAP, self.heap - HEAP))),
                          (PATH_BUFFER, bytes(self.mu.mem_read(PATH_BUFFER, 0x800)))],
                     heap=self.heap, sizes=self.sizes, resources=self.resources, tick=self.tick)
        if registers:
            from unicorn import x86_const
            esp = self.esp()
            state['mem'].append((esp, bytes(self.mu.mem_read(esp, STACK_TOP + 0x100 - esp))))
            state['registers'] = {name: self.mu.reg_read(getattr(x86_const, f'UC_X86_REG_{name}')) for name in REGISTERS}
        return state

    def restore(self, state: dict) -> None:
        for base, blob in state['mem']:
            self.mu.mem_write(base, blob)
        self.heap, self.sizes, self.resources, self.tick = state['heap'], dict(state['sizes']), dict(state['resources']), state['tick']
        if 'registers' in state:
            from unicorn import x86_const
            for name, value in state['registers'].items():
                self.mu.reg_write(getattr(x86_const, f'UC_X86_REG_{name}'), value)

    # ---- frames
    def install_frame_stubs(self, keep: tuple[int, ...] = ()) -> None:
        """The frame shims of SHIMS; `keep` names addresses (0x45f724 for the draw-pass skip)
        left original — the ablation switch."""
        if DRAW_SKIP[0] not in keep:
            self.jump(*DRAW_SKIP)
        for at, label in FRAME_STUBS:
            if at in keep:
                continue
            if at == PRESENT:
                self.hook(at, lambda label=label: (self.put(PRESENTED, 1), self.stub_hits.update([label]), self.ret(0)))
            else:
                self.stub(at, 0, label)

    def frame(self) -> None:
        self.call(FRAME_BODY)


def cache_path(exe_sha: str, save_sha: str, level: int) -> Path:
    return CACHE_DIR / f'v{CACHE_VERSION}_{exe_sha[:12]}_{save_sha[:12]}_L{level}.pkl'


def loaded_machine(exe: Path, save: bytes, level: int, use_cache: bool = True) -> tuple[BattleMachine, dict]:
    """A machine with the save loaded; info records whether the cache was used and the
    global-RNG draws the load itself made (sites and counts)."""
    save_sha = hashlib.sha256(save).hexdigest()
    machine = BattleMachine(exe, save)
    path = cache_path(EXE_SHA, save_sha, level)
    if use_cache and path.exists():
        state = pickle.loads(path.read_bytes())
        machine.restore(state)
        return machine, dict(cache='hit', path=path.relative_to(ROOT).as_posix(), load=state['load'])
    draws: Counter = Counter()

    def count_draw():   # a raw draw inside rand(n) 0x458c80 is attributed to rand's caller
        back = machine.return_address()
        site = machine.get(machine.esp() + 8) if back in RAND_INNER_RETURNS else back
        draws[f'{site - 5:#x}'] += 1
    handle = machine.hook(0x458c10, count_draw)
    machine.boot_and_load(level)
    machine.unhook(handle)
    load = dict(global_draws=dict(sorted(draws.items())), tick=machine.tick, imports=dict(sorted(machine.imports_hit.items())))
    if use_cache:
        state = machine.snapshot()
        state['load'] = load
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(pickle.dumps(state))
    return machine, dict(cache='built', path=path.relative_to(ROOT).as_posix(), load=load)
