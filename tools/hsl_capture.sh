#!/usr/bin/env bash
# Bounded, window-only capture harness for the user's local original HSL copy.
# It never runs from automated tests and writes only under ignored/captures/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WINDOW_FINDER="$SCRIPT_DIR/hsl_window"
INPUT_HELPER="$SCRIPT_DIR/hsl_input"
PYTHON_BIN="${PYTHON_BIN:-$([[ -x /opt/homebrew/bin/python3 ]] && echo /opt/homebrew/bin/python3 || command -v python3 || echo python3)}"
DEFAULT_ROUTE="$SCRIPT_DIR/routes/p1_title_to_player_control.txt"

usage() {
  cat <<'USAGE'
usage: tools/hsl_capture.sh [--no-launch] [--dry-run] [ROUTE_FILE]

Options:
  --no-launch  attach to an already running original HSL window
  --dry-run    validate and print the route without finding a window or sending input
  -h, --help   show this help

Route actions:
  click X Y          raw HID left click; used for title/dialogue progression
  rclick X Y         restored HID right click
  menuclick X Y      restored HID left click for battle command menus
  menurclick X Y     restored HID right click for battle command menus
  move X Y           HID pointer move without click
  key NAME           HID key (space/return/escape/up/down/left/right/tab)
  wait SECONDS       wait, then capture
  screenshot [LABEL] capture without input

Input actions require macOS Accessibility permission for tools/hsl_input.
All screenshots are window-only; the desktop is never captured.
USAGE
}

NO_LAUNCH=0
DRY_RUN=0
ROUTE_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launch) NO_LAUNCH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)
      if [[ -n "$ROUTE_FILE" ]]; then
        echo "only one route file may be supplied" >&2
        exit 2
      fi
      ROUTE_FILE="$1"
      ;;
  esac
  shift
done
ROUTE_FILE="${ROUTE_FILE:-$DEFAULT_ROUTE}"

if [[ ! -f "$ROUTE_FILE" ]]; then
  echo "route file not found: $ROUTE_FILE" >&2
  exit 2
fi

is_integer() { [[ "$1" =~ ^-?[0-9]+$ ]]; }
is_seconds() { [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; }

validate_route() {
  local line raw action args x y extra line_number=0 step_count=0
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line_number=$((line_number + 1))
    line="${raw%%#*}"
    line="$(printf '%s' "$line" | xargs 2>/dev/null || true)"
    [[ -z "$line" ]] && continue
    read -r action args <<< "$line"
    case "$action" in
      click|rclick|menuclick|menurclick|move)
        read -r x y extra <<< "$args"
        if ! is_integer "${x:-}" || ! is_integer "${y:-}" || [[ -n "${extra:-}" ]]; then
          echo "$ROUTE_FILE:$line_number: $action requires exactly two integer coordinates" >&2
          return 2
        fi
        ;;
      key)
        case "$args" in
          space|return|enter|escape|esc|up|down|left|right|tab|[a-z]) ;;
          *) echo "$ROUTE_FILE:$line_number: unsupported key: $args" >&2; return 2 ;;
        esac
        ;;
      wait)
        if ! is_seconds "$args"; then
          echo "$ROUTE_FILE:$line_number: wait requires non-negative seconds" >&2
          return 2
        fi
        ;;
      screenshot) ;;
      *) echo "$ROUTE_FILE:$line_number: unknown route action: $action" >&2; return 2 ;;
    esac
    step_count=$((step_count + 1))
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf '%03d  %s\n' "$step_count" "$line"
    fi
  done < "$ROUTE_FILE"
  if [[ "$step_count" -eq 0 ]]; then
    echo "route contains no executable actions: $ROUTE_FILE" >&2
    return 2
  fi
  echo "route valid: $ROUTE_FILE ($step_count actions)"
}

validate_route
if [[ "$DRY_RUN" -eq 1 ]]; then
  exit 0
fi

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python 3.10+ not found: $PYTHON_BIN" >&2
  exit 1
fi
if [[ ! -x "$WINDOW_FINDER" || ! -x "$INPUT_HELPER" ]]; then
  "$SCRIPT_DIR/build_runtime_helpers.sh"
fi

if [[ "$NO_LAUNCH" -eq 0 ]]; then
  echo "launching original HSL..."
  "$SCRIPT_DIR/run_original_hsl.sh" >/dev/null 2>&1 &
  echo "launcher pid: $!"
fi

echo "waiting for the HSL window (up to 15 seconds)..."
WINDOW_JSON=$("$WINDOW_FINDER" --wait 15) || {
  echo "HSL window not found" >&2
  exit 1
}
WINDOW_ID=$(printf '%s' "$WINDOW_JSON" | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["window_id"])')

TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
mkdir -p "$PROJECT_DIR/ignored/captures"
CAPTURE_DIR="$(mktemp -d "$PROJECT_DIR/ignored/captures/${TIMESTAMP}.XXXXXX")"
TRACE_JSONL="$CAPTURE_DIR/trace.jsonl"
printf '%s\n' "$WINDOW_JSON" > "$CAPTURE_DIR/window.json"
: > "$TRACE_JSONL"

echo "capture session: $CAPTURE_DIR"
echo "window: $WINDOW_JSON"

STEP_NUM=0
capture_screenshot() {
  local output
  output=$(printf '%s/step_%03d.png' "$CAPTURE_DIR" "$STEP_NUM")
  screencapture -x -o -l"$WINDOW_ID" "$output"
  if [[ ! -s "$output" ]]; then
    echo "window capture failed: $output" >&2
    exit 1
  fi
  basename "$output"
}

append_trace() {
  local action="$1" detail="$2" screenshot="$3"
  "$PYTHON_BIN" - "$TRACE_JSONL" "$STEP_NUM" "$action" "$detail" "$screenshot" <<'PY'
import json
import sys
import time
from pathlib import Path

path = Path(sys.argv[1])
entry = {
    "step": int(sys.argv[2]),
    "action": sys.argv[3],
    "detail": sys.argv[4],
    "screenshot": sys.argv[5],
    "timestamp": int(time.time()),
}
with path.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
PY
}

record_step() {
  local action="$1" detail="$2" screenshot
  screenshot=$(capture_screenshot)
  append_trace "$action" "$detail" "$screenshot"
  echo "step $STEP_NUM: $action $detail -> $screenshot"
  STEP_NUM=$((STEP_NUM + 1))
}

sleep 2
record_step "initial" "game_window_ready"

line_number=0
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line_number=$((line_number + 1))
  line="${raw%%#*}"
  line="$(printf '%s' "$line" | xargs 2>/dev/null || true)"
  [[ -z "$line" ]] && continue
  read -r action args <<< "$line"
  case "$action" in
    click)
      read -r x y <<< "$args"
      "$INPUT_HELPER" --window-id "$WINDOW_ID" rawclick "$x" "$y"
      sleep 0.8
      record_step "click" "$x,$y"
      ;;
    rclick)
      read -r x y <<< "$args"
      "$INPUT_HELPER" --window-id "$WINDOW_ID" rclick "$x" "$y"
      sleep 0.8
      record_step "rclick" "$x,$y"
      ;;
    menuclick)
      read -r x y <<< "$args"
      "$INPUT_HELPER" --window-id "$WINDOW_ID" menuclick "$x" "$y"
      sleep 0.8
      record_step "menuclick" "$x,$y"
      ;;
    menurclick)
      read -r x y <<< "$args"
      "$INPUT_HELPER" --window-id "$WINDOW_ID" menurclick "$x" "$y"
      sleep 0.8
      record_step "menurclick" "$x,$y"
      ;;
    move)
      read -r x y <<< "$args"
      "$INPUT_HELPER" --window-id "$WINDOW_ID" move "$x" "$y"
      sleep 0.4
      record_step "move" "$x,$y"
      ;;
    key)
      "$INPUT_HELPER" --window-id "$WINDOW_ID" keyhid "$args"
      sleep 0.8
      record_step "key" "$args"
      ;;
    wait)
      sleep "$args"
      record_step "wait" "${args}s"
      ;;
    screenshot)
      record_step "screenshot" "${args:-manual}"
      ;;
  esac
done < "$ROUTE_FILE"

"$PYTHON_BIN" - "$TRACE_JSONL" "$CAPTURE_DIR/trace.json" "$ROUTE_FILE" "$WINDOW_JSON" <<'PY'
import json
import sys
from pathlib import Path

jsonl = Path(sys.argv[1])
out = Path(sys.argv[2])
steps = [json.loads(line) for line in jsonl.read_text(encoding="utf-8").splitlines() if line]
payload = {
    "schema": "hsl_window_capture.v2",
    "route_file": sys.argv[3],
    "window": json.loads(sys.argv[4]),
    "step_count": len(steps),
    "steps": steps,
}
out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
rm -f "$TRACE_JSONL"

echo "capture complete: $CAPTURE_DIR"
echo "trace: $CAPTURE_DIR/trace.json"
