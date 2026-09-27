#!/usr/bin/env bash
# Lane verification as one plain command, the lane environment built in (AGENTS.md 效率节拍):
#   tools/lane_verify.sh affected BASE [SUITE...]  while working: the registry checks `hsl affected --since BASE
#                                                  --check` selects, the tools/test_hsl_*.py files and Godot suites
#                                                  the change hits, `bash -n` on changed scripts, plus any SUITE named
#                                                  (tools/verify_runner.py affected; one Godot process at a time)
#   tools/lane_verify.sh fast                      before the report: one fast gate tools/verify.sh (it queues for the
#                                                  shared verify slot, tools/verify_slot.sh)
# Environment: PYTHONDONTWRITEBYTECODE=1 and HSL_VERIFY_JOBS (default 3) are set here. HOME is left alone: every
# Godot suite already runs in its own HOME under ignored/gate-homes/ (tools/verify_runner.py), and the Python tools
# read HOME only for the WINEPREFIX default. The full log goes to ignored/lane-verify/<mode>-<HEAD>.log; the terminal
# gets the stage result lines, each failure block (last 30 lines) and a final LANE_VERIFY_PASS|FAIL line.
# Why: on 2026-09-25 at least five lanes hit the worktree guard rejecting a `HOME=` prefix or a compound command,
# and lanes ran about 31 fast gates (about 300 machine-minutes) where targeted checks were enough.
# Bash 3.2 compatible.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PYTHONDONTWRITEBYTECODE=1
export HSL_VERIFY_JOBS="${HSL_VERIFY_JOBS:-3}"
PYTHON_BIN="${PYTHON_BIN:-$([[ -x /opt/homebrew/bin/python3 ]] && echo /opt/homebrew/bin/python3 || command -v python3 || echo python3)}"
LOG_DIR="$ROOT/ignored/lane-verify"
HEAD_SHORT="$(git rev-parse --short HEAD)"
# Result lines worth a lane's context: stage summaries, slot waits, failures. The per-task "  <- name" block of the
# checks stays in the log; per-suite Godot lines ("  <- suite Ns") are shown in affected mode only.
SHOW='^(VERIFY_|LANE_AFFECTED|== |\[[A-Z_]+ FAIL |  FAILED: |[A-Z0-9_]+_(PASS|FAIL|SUMMARY)( |$))'

usage() { sed -n '2,8p' "$0" >&2; exit 2; }

run_logged() {  # MODE HIDE_REGEX COMMAND...
  local mode="$1" hide="$2" log ec
  shift 2
  mkdir -p "$LOG_DIR"
  log="$LOG_DIR/${mode}-${HEAD_SHORT}.log"
  set +e
  "$@" 2>&1 | tee "$log" | grep --line-buffered -E "$SHOW" | grep --line-buffered -v -E "$hide"
  ec="${PIPESTATUS[0]}"
  set -e
  if [ "$ec" -ne 0 ]; then
    awk '/^\[[A-Z_]+ FAIL /{inb=1; n=0} inb{buf[n++]=$0}
         /^\[end of /{ if (inb) { s = (n > 30 ? n - 30 : 0); if (s) print "  ... (" s " earlier lines in the log)";
                                  for (i = s; i < n; i++) print buf[i]; inb = 0 } }' "$log"
    echo "--- last lines of the log ---"
    tail -8 "$log"
    echo "LANE_VERIFY_FAIL mode=${mode} head=${HEAD_SHORT} exit=${ec} log=${log}"
    return "$ec"
  fi
  echo "LANE_VERIFY_PASS mode=${mode} head=${HEAD_SHORT} $(tail -1 "$log") log=${log}"
}

cmd="${1:-}"
shift || true
case "$cmd" in
  affected)
    [ $# -ge 1 ] || usage
    base="$1"
    shift
    git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || { echo "LANE_VERIFY_FAIL unknown base ${base}" >&2; exit 2; }
    run_logged affected '  <- [^ ]+$' "$PYTHON_BIN" tools/verify_runner.py affected --since "$base" "$@"
    ;;
  fast)
    [ $# -eq 0 ] || usage
    run_logged fast '  <- ' tools/verify.sh
    ;;
  *)
    usage
    ;;
esac
