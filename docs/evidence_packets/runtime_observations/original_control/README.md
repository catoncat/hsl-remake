# Original HSL: bounded Wine-side control

> evidence: runtime-measured · status: record-only · tools: build_runtime_helpers.sh, hsl_original_control.py, hsl_runtime_probe.py · updated: 2026-09-09

Evidence tier: `runtime-measured`. Checked on 2026-09-09 using the user's local
HSL v1.06 title screen, Wine 11.0 and the already installed cnc-ddraw wrapper.
This packet validates a control/capture route, not remake parity or all gameplay.

## Working route

Use `tools/hsl_original_control.py`: one Win32 action in the same Wine prefix,
then cnc-ddraw's own 640×480 surface screenshot. Inspect that screenshot before
choosing another action. The tool never infers gameplay success from SendInput's
return value, nor automatically retries an action after a screenshot failure.

```sh
tools/build_runtime_helpers.sh --win32-control
python3 tools/hsl_original_control.py inspect
python3 tools/hsl_original_control.py screenshot --label before

# Precondition: visually confirmed first-turn action menu, with Move at 367,175.
python3 tools/hsl_original_control.py click 367 175 --dry-run
python3 tools/hsl_original_control.py click 367 175 --label move
# Inspect the emitted game.png; proceed only when movement selection is visible.
python3 tools/hsl_original_control.py rclick 320 240 --label cancel
```

`inspect` is read-only and emits no screenshot. `focus` explicitly requests Wine
foreground focus; ordinary inputs refuse when the game is not Wine's foreground
window. `key space`, `key enter`, `key escape`, arrows and tab are supported.
Only Space was exercised during opening/confirmation in this proof. Inputs use
640×480 logical client coordinates, not macOS points. Each non-inspect action
records its receipt before attempting a screenshot; a failure must be inspected
before replaying anything.

The helper uniquely resolves `hsl01.exe` and its game window; ambiguous processes
or windows fail instead of guessing. Captures reject stale PNGs, ambiguous new
files, unexpected dimensions and a changed Wine PID/HWND. The screenshot hotkey
is an additional input, not a perfectly passive recorder.

## Runtime observations

- Original Windows client: 640×480; native macOS window: 577×462 points.
  The previous helper's minimum 600×470 rejected this window. Both Swift helpers
  now admit downscaling while retaining Wine owner, layer, aspect and ambiguity
  checks. These checks remain heuristic; the new bridge identifies the EXE.
- `screencapture -l358` failed to create a window image even though the screen
  capture permission preflight returned true. A separate Win32 BitBlt client
  capture experiment also failed. Neither is used by the new bridge.
- The installed `ddraw.ini` already specified `renderer=gdi`, `windowed=true`,
  `keyscreenshot=0x2C`, and `screenshotdir=.\Screenshots\`. Sending VK_SNAPSHOT
  inside Wine produced a fresh, visually verified game PNG. No config was changed.
- EXE imports include `GetKeyboardState` and `GetKeyState`; the import table did
  not directly name DirectInput. This does not exclude dynamic API loading and
  does not establish every internal input path.
- The prototype entered New Story (first click highlighted, second activated),
  passed opening dialogue/conditions using Space and one dialogue mouse click,
  and reached the first battle action menu.
- Three consecutive prototype cycles of single left click at `(367,175)` then
  single right click at `(320,240)` showed movement selection and return to the
  action menu. All six frames were visually reviewed together. The promoted
  tool then repeated the same cycle successfully; the two frames and receipts
  are preserved in this packet's `proof.json`.

Raw prototype records: `ignored/original-control-spike/probe.jsonl` and
`move-proof.png`; promoted-tool receipts: `ignored/original-control/`.
Raw paths are optional diagnostics, not tracked dependencies.

## Boundaries

No EXE patch, game-memory write, save overwrite, gameplay-stat change or Godot
product change was used. cnc-ddraw writes new screenshot files inside the game
installation; the tool copies them to a unique ignored evidence directory.

This is **not isolated/headless control**. Wine foreground state does not prove
macOS foreground state; inputs may move the actual pointer, and user interaction
can interfere. Use short supervised operations on the built-in display, not an
unattended playthrough. External displays, background-only control, other Wine
versions/renderers, actual move destinations, attacks, items, complete battles
and long-run reliability were not validated here. A fresh PNG may depict a valid
black transition or an unchanged game state; `behavior_verified` stays false in
machine receipts until separate visual review.

The pre-existing `hsl_runtime_probe.py`/`hsl_win32_memread.c` remain candidates for
read-only state observations when a precise rule question needs them. This input
proof did not run or validate those memory probes.

## API basis

Microsoft documents SendInput as inserting events into the keyboard/mouse input
stream; its return value reports insertion, not application-level acceptance.
GetKeyboardState reflects the calling thread's keyboard state. Posting key
messages alone is not equivalent to injecting keyboard input. References:

- Microsoft Learn, `SendInput function (winuser.h)`.
- Microsoft Learn, `GetKeyboardState function (winuser.h)`.
- Microsoft The Old New Thing, `You can't simulate keyboard input with PostMessage, revisited` (2025-03-19).
