#!/usr/bin/env bash
# Canonical non-GUI verification for the current repository.
#
#   tools/verify.sh            fast gate (default): warm Godot cache, parallel checks and suites
#   tools/verify.sh --full     full gate: additionally proves the cold-clone import by deleting
#                              .godot and every untracked *.import first
#   tools/verify.sh --deep     deep gate: the fast gate, then the long end-to-end suites
#                              (tools/verify_runner.py deep: the story-mode explorer) last
#   --jobs=N                   parallel workers for the Python checks and Godot suites
#
# Every mode runs every check and every suite (tools/verify_runner.py enumerates them from the
# repository data, not from a hand-written list). Nothing is deleted on exit: the import cache
# stays warm for the next focused test or gate run. See docs/internal/CONSOLIDATION.md P0 and
# docs/internal/PLAYABILITY.md R0.
#
# At most two runs execute at once on this machine (tools/verify_slot.sh): the lead gate
# (HSL_VERIFY_PRIORITY=1, set by tools/lane_merge.sh gate) has its own slot, every other run
# shares the second one and prints VERIFY_WAIT every 30 s while it queues.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/python3}}"
PYTHON_BIN="${PYTHON_BIN:-$([[ -x /opt/homebrew/bin/python3 ]] && echo /opt/homebrew/bin/python3 || command -v python3 || echo python3)}"
GODOT_BIN="${GODOT_BIN:-$([[ -x /opt/homebrew/bin/godot ]] && echo /opt/homebrew/bin/godot || command -v godot || echo godot)}"
export PYTHONDONTWRITEBYTECODE=1

MODE=fast
JOBS=()
for arg in "$@"; do
  case "$arg" in
    --fast) MODE=fast ;;
    --full) MODE=full ;;
    --deep) MODE=deep ;;
    --jobs=*) JOBS=(--jobs "${arg#--jobs=}") ;;
    *) echo "usage: tools/verify.sh [--fast|--full|--deep] [--jobs=N]" >&2; exit 2 ;;
  esac
done

cleanup_generated_cache() {
  # The full gate must import from a cold clone. Never delete a force-tracked cache file.
  if [[ -z "$(git -C "$ROOT" ls-files -- .godot)" ]]; then
    rm -rf -- "$ROOT/.godot"
  fi
  while IFS= read -r -d '' relpath; do
    rm -f -- "$ROOT/$relpath"
  done < <(git -C "$ROOT" ls-files --others -i --exclude-standard -z -- '*.import')
}

run_godot() {
  GODOT_BIN="$GODOT_BIN" "$ROOT/tools/godot.sh" "$@"
}

cd "$ROOT"
# shellcheck source=tools/verify_slot.sh
source "$SCRIPT_DIR/verify_slot.sh"
verify_slot_acquire
started=$SECONDS

# Original-derived content absent (a public checkout before the import, hsltools.original_content):
# the registry and the Python stage report SKIP original-absent, the Godot stages are skipped whole.
ORIGINAL_PRESENT=1
"$PYTHON_BIN" -c 'import sys; sys.path.insert(0, "tools"); from hsltools import original_content; sys.exit(0 if original_content.present() else 1)' \
  || ORIGINAL_PRESENT=0

# Cheap checks first: syntax, whitespace hygiene, doc links and JSON parse fail in seconds,
# before the minutes-long Python, check and Godot stages.
echo "== source syntax =="
for script in tools/*.sh; do
  bash -n "$script"
done
if command -v swiftc >/dev/null; then
  swiftc -typecheck tools/hsl_window.swift -framework CoreGraphics
  swiftc -typecheck tools/hsl_input.swift -framework AppKit
  swiftc -parse-as-library -typecheck tools/hsl_record_window.swift
fi

echo "== repository hygiene =="
git diff HEAD --check
# Committed content too (lanes verify on a clean tree, where `diff HEAD` sees nothing):
# every tracked text file except original imports, vendored external docs and SVG art.
git diff --check 4b825dc642cb6eb9a060e54bf8d69288fbee4904 HEAD -- . \
  ':(exclude)content/imported/' ':(exclude)docs/external/' ':(exclude)*.svg'
"$PYTHON_BIN" tools/hsl_docs_check.py
"$PYTHON_BIN" - <<'PY'
import json
import subprocess
from pathlib import Path

raw = subprocess.check_output(
    ["git", "ls-files", "-co", "--exclude-standard", "-z", "--", "*.json"]
)
files = sorted({Path(item.decode()) for item in raw.split(b"\0") if item})
existing = [path for path in files if path.exists()]
for path in existing:
    json.loads(path.read_text(encoding="utf-8"))
print(f"CURRENT_JSON_PARSE_PASS count={len(existing)}")
PY

echo "== doctor =="
step_started=$SECONDS
tools/doctor.sh
echo "DOCTOR_STEP_PASS seconds=$((SECONDS - step_started))"

echo "== Python unit tests =="
"$PYTHON_BIN" tools/verify_runner.py python-tests ${JOBS[@]+"${JOBS[@]}"}

echo "== source, evidence and importer checks =="
"$PYTHON_BIN" tools/verify_runner.py checks ${JOBS[@]+"${JOBS[@]}"}

if [[ "$ORIGINAL_PRESENT" == 1 ]]; then
  echo "== Godot asset import ($MODE) =="
  if [[ "$MODE" == full ]]; then
    cleanup_generated_cache
    export HSL_GODOT_SEED=0  # prove the cold import: tools/godot.sh must not seed .godot from another worktree
  fi
  step_started=$SECONDS
  run_godot --headless --import
  echo "GODOT_IMPORT_PASS mode=$MODE seconds=$((SECONDS - step_started))"

  echo "== Godot headless suites =="
  GODOT_BIN="$GODOT_BIN" "$PYTHON_BIN" tools/verify_runner.py godot ${JOBS[@]+"${JOBS[@]}"}
else
  echo "GODOT_SUITES_SKIP original-absent (the Godot import and suites load content/: import the original first)"
fi

if [[ "$MODE" == deep && "$ORIGINAL_PRESENT" == 1 ]]; then
  echo "== Godot deep suites =="
  GODOT_BIN="$GODOT_BIN" "$PYTHON_BIN" tools/verify_runner.py deep ${JOBS[@]+"${JOBS[@]}"}
fi

echo "VERIFY_PASS mode=$MODE seconds=$((SECONDS - started))"
