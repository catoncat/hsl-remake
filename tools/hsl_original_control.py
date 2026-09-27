#!/usr/bin/env python3
"""One bounded original-game action plus a fresh cnc-ddraw surface screenshot.

This is not a playthrough bot. Inspect each screenshot before choosing another
action. It never launches the game, writes process memory or edits game files.
cnc-ddraw's existing screenshot hotkey writes its own PNG in hsl/Screenshots.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))  # hsltools
from hsltools.paths import WINE_PREFIX

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "ignored/bin/hsl_win32_control.exe"
KEYS = {"space", "enter", "escape", "left", "right", "up", "down", "tab"}


def command_for(action: str, operands: list[str], hold_ms: int) -> list[str]:
    if not 20 <= hold_ms <= 1000:
        raise ValueError("hold must be 20..1000 milliseconds")
    if action in {"inspect", "focus", "screenshot"} and not operands:
        return ["inspect" if action == "screenshot" else action]
    if action == "place" and len(operands) == 2:
        x, y = (int(value) for value in operands)
        if 0 <= x < 4000 and 0 <= y < 4000:
            return [action, str(x), str(y)]
    if action == "key" and len(operands) == 1 and operands[0] in KEYS:
        return [action, operands[0], str(hold_ms)]
    if action in {"move", "click", "rclick"} and len(operands) == 2:
        x, y = (int(value) for value in operands)
        if 0 <= x < 640 and 0 <= y < 480:
            return [action, str(x), str(y)] + ([] if action == "move" else [str(hold_ms)])
    raise ValueError("invalid action/operands; coordinates are 0..639, 0..479 (place: desktop 0..3999)")


def scan_captures(directory: Path) -> dict[Path, tuple[int, int]]:
    return {path: (path.stat().st_mtime_ns, path.stat().st_size)
            for path in directory.glob("*.png")}


def wait_for_capture(directory: Path, before: dict[Path, tuple[int, int]],
                     timeout: float = 5) -> Path:
    from PIL import Image

    deadline = time.monotonic() + timeout
    while True:
        changed = [path for path, stat in scan_captures(directory).items()
                   if before.get(path) != stat]
        if len(changed) > 1:
            raise RuntimeError("multiple changed screenshots; capture identity is ambiguous")
        if changed:
            try:
                with Image.open(changed[0]) as image:
                    image.load()
                    if image.size != (640, 480):
                        raise RuntimeError(f"unexpected game surface size: {image.size}")
                return changed[0]
            except OSError:
                pass  # The wrapper may still be writing the new file.
        if time.monotonic() >= deadline:
            raise TimeoutError("no fresh 640x480 PNG; check cnc-ddraw keyscreenshot=0x2C and screenshotdir=.\\Screenshots\\")
        time.sleep(0.05)


def check_identity(action: dict, screenshot: dict) -> None:
    for field in ("pid", "hwnd"):
        if field not in action or action[field] != screenshot.get(field):
            raise RuntimeError("game identity changed between action and screenshot")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inspect", "focus", "place", "screenshot", "key", "move", "click", "rclick"))
    parser.add_argument("operands", nargs="*")
    parser.add_argument("--hold-ms", type=int, default=160)
    parser.add_argument("--label", default="probe")
    parser.add_argument("--dry-run", action="store_true", help="validate and print without running Wine or writing files")
    parser.add_argument("--focus", action="store_true", help="explicitly focus the game in the input helper; may interrupt desktop focus")
    args = parser.parse_args()
    try:
        command = command_for(args.action, args.operands, args.hold_ms)
        if args.focus and args.action not in {"inspect", "focus", "place", "screenshot"}:
            command.insert(0, "--focus")
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", args.label):
            raise ValueError("label must be 1..64 ASCII letters, digits, underscores or hyphens")
    except ValueError as error:
        parser.error(str(error))

    if args.dry_run:
        print(json.dumps({"helper": str(HELPER), "command": command,
                          "screenshot_command": None if args.action in {"inspect", "place"} else ["key", "snapshot"]}))
        return 0
    if not HELPER.is_file():
        parser.error("build helper first: tools/build_runtime_helpers.sh --win32-control")

    prefix = WINE_PREFIX.resolve()
    directory = prefix / "drive_c/hsl/Screenshots"
    env = dict(os.environ, WINEPREFIX=str(prefix), WINEDEBUG="-all")
    wine = os.environ.get("WINE_BIN", "/opt/homebrew/bin/wine")

    def call(operands: list[str]) -> dict:
        result = subprocess.run([wine, str(HELPER), *operands], env=env,
                                capture_output=True, text=True, timeout=8)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip())
        return json.loads(result.stdout)

    capture_dir: Path | None = None
    try:
        if args.action in {"inspect", "place"}:
            print(json.dumps(call(command), ensure_ascii=False))
            return 0
        output_root = ROOT / "ignored/original-control"
        output_root.mkdir(parents=True, exist_ok=True)
        capture_dir = Path(tempfile.mkdtemp(prefix=f"{args.label}-", dir=output_root))
        record = {"schema": "hsl_original_control.v1", "action": command,
                  "prefix": str(prefix), "timestamp": time.time(),
                  "behavior_verified": False}
        # Record input before capture: a screenshot failure must not hide that
        # an action was already sent. Never retry gameplay input automatically.
        record["input"] = call(command)
        (capture_dir / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
        time.sleep(0.35)
        before = scan_captures(directory)
        record["capture_input"] = call(["key", "snapshot"])
        check_identity(record["input"], record["capture_input"])
        source = wait_for_capture(directory, before)
        target = capture_dir / "game.png"
        shutil.copy2(source, target)
        record.update(source=str(source), screenshot=str(target),
                      sha256=hashlib.sha256(target.read_bytes()).hexdigest())
        (capture_dir / "receipt.json").write_text(json.dumps(record, indent=2) + "\n")
        print(json.dumps(record, ensure_ascii=False, indent=2))
        return 0
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        print(json.dumps({"status": "error", "error": str(error),
                          "capture_dir": str(capture_dir) if capture_dir else None,
                          "warning": "an action may already have been sent; inspect before retrying"}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
