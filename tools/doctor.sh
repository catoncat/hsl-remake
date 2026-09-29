#!/usr/bin/env bash
# Read-only environment and repository preflight. Does not launch Wine or Godot UI.
# The checks live in tools/hsltools/doctor.py (`python tools/hsl.py doctor`, also on Windows); this wrapper
# keeps the historical entry and its Homebrew Python default (PYTHON_BIN, GODOT_BIN, WINE_BIN and
# CLICLICK_BIN are honoured as before).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# An active virtualenv (where requirements-dev.txt goes on a PEP 668 Python such as Homebrew's) comes first.
PYTHON_BIN="${PYTHON_BIN:-${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/python3}}"
PYTHON_BIN="${PYTHON_BIN:-/opt/homebrew/bin/python3}"
[[ -x "$PYTHON_BIN" ]] || PYTHON_BIN="$(command -v python3 || true)"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--original" ) ]]; then
  echo "usage: tools/doctor.sh [--original]" >&2
  exit 2
fi
if [[ -z "$PYTHON_BIN" ]]; then
  echo "FAIL  Python executable missing (set PYTHON_BIN)"
  echo "doctor failed: errors=1 warnings=0" >&2
  exit 1
fi
exec "$PYTHON_BIN" "$ROOT/tools/hsl.py" doctor "$@"
