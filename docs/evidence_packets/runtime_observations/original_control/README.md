# Original HSL: bounded Wine-side control

> evidence: runtime-measured · status: record-only · tools: build_runtime_helpers.sh, hsl_original_control.py, hsl_runtime_probe.py · updated: 2026-09-27

## 结论

- Original: HSL v1.06 under Wine 11.0 with the installed cnc-ddraw wrapper accepts one Win32 input at a time in 640×480 logical client coordinates, and cnc-ddraw's own screenshot hotkey (VK_SNAPSHOT) yields a fresh 640×480 game PNG; a click at the Move icon `(367,175)` then a right click at `(320,240)` enters and leaves movement selection (runtime-measured).
- Remake: not a remake packet — it validates a supervised control/capture route (`tools/hsl_original_control.py`) used by other original-side packets; no Godot product code consumes it (runtime-measured).
- Difference: none claimed; this is not isolated or headless control, and does not prove remake parity or any gameplay rule (negative-evidence for unattended use).

## 证据

**runtime-measured (HSL v1.06 title screen, Wine 11.0, cnc-ddraw)**

| Observation | Reading |
| --- | --- |
| Client size | Original Windows client 640×480; native macOS window 577×462 points. The earlier helper minimum 600×470 rejected this window; both Swift helpers now admit downscaling while keeping Wine owner, layer, aspect and ambiguity checks (heuristic; the bridge identifies the EXE). |
| Failed captures | `screencapture -l358` failed to create a window image although the screen-capture preflight returned true; a Win32 BitBlt client-capture experiment also failed. Neither is used. |
| cnc-ddraw config | Installed `ddraw.ini`: `renderer=gdi`, `windowed=true`, `keyscreenshot=0x2C`, `screenshotdir=.\Screenshots\`. VK_SNAPSHOT inside Wine produced a fresh, visually verified PNG. No config was changed. |
| Input imports | EXE imports `GetKeyboardState` and `GetKeyState`; the import table does not name DirectInput (does not exclude dynamic loading). |
| Opening route | New Story (first click highlights, second activates) → opening dialogue/conditions passed with Space and one dialogue mouse click → first battle action menu. |
| Move/cancel cycle | Three prototype cycles of left click `(367,175)` then right click `(320,240)` showed movement selection and return to the action menu (six frames reviewed together); the promoted tool repeated the cycle — frames move-selected.png（原版帧见私有档案：`runtime_observations/original_control/move-selected.png`）, cancel-returned.png（原版帧见私有档案：`runtime_observations/original_control/cancel-returned.png`）, receipts in [proof.json](proof.json). |

**API basis (external documentation)**: SendInput inserts events into the keyboard/mouse input stream and its return value reports insertion, not application-level acceptance (Microsoft Learn, `SendInput function (winuser.h)`); GetKeyboardState reflects the calling thread's keyboard state (Microsoft Learn, `GetKeyboardState function (winuser.h)`); posting key messages alone is not equivalent to injecting input (The Old New Thing, `You can't simulate keyboard input with PostMessage, revisited`, 2025-03-19).

## 重制接线

No `game/` consumer. Tool contract of `tools/hsl_original_control.py`:

- One Win32 action in the same Wine prefix, then a cnc-ddraw 640×480 screenshot; inspect it before the next action. Never infers success from SendInput's return value; never auto-retries after a screenshot failure.
- `inspect` is read-only (no screenshot). `focus` requests Wine foreground; ordinary inputs refuse when the game is not Wine's foreground window. `key space|enter|escape`, arrows and tab are supported (only Space was exercised here). Each non-inspect action records its receipt before the screenshot.
- Uniquely resolves `hsl01.exe` and its window (ambiguity fails); captures reject stale PNGs, ambiguous new files, unexpected dimensions and a changed Wine PID/HWND. The screenshot hotkey is itself an input, not a passive recorder.
- `hsl_runtime_probe.py`／`hsl_win32_memread.c` are separate read-only memory probes; this route did not run them.

## 复现

`tools/build_runtime_helpers.sh --win32-control && python3 tools/hsl_original_control.py inspect`, then with a visually confirmed first-turn action menu: `python3 tools/hsl_original_control.py click 367 175 --label move` and `rclick 320 240 --label cancel`, inspecting each emitted `game.png` before continuing. Readings above are 不可再生：原版侧唯一记录 for the tested Wine/cnc-ddraw setup.

## 边界

- No EXE patch, game-memory write, save overwrite, gameplay-stat change or Godot change was used; cnc-ddraw writes screenshots inside the game installation and the tool copies them to a unique ignored directory.
- Not isolated/headless: Wine foreground does not prove macOS foreground; inputs may move the real pointer and interaction can interfere. Short supervised operations on the built-in display only.
- Not validated: external displays, background-only control, other Wine versions/renderers, move destinations, attacks, items, complete battles, long-run reliability.
- A fresh PNG may show a valid black transition or an unchanged state; `behavior_verified` stays false in receipts until separate visual review.
