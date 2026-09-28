#!/usr/bin/env bash
# Run Godot in this checkout and fail on diagnostics even when Godot exits zero.
# Import explicitly with --headless --import before running focused tests.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found; set GODOT_BIN or install Godot." >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "usage: tools/godot.sh GODOT_ARGS... (use tools/play.sh to play)" >&2
  exit 2
fi

# Test scripts run directly (tools/godot.sh --script res://tests/...) get the same default random
# seed the gate runners export, so a suite gives one answer regardless of the wall clock.
if [[ " $* " == *" res://tests/"* && -z "${HSL_RNG_SEED:-}" ]]; then
  export HSL_RNG_SEED=1
fi

# A fast-clock suite (FAST_CLOCK_SUITES in tools/verify_runner.py) run directly gets the gate's
# --fixed-fps 60 unless the caller gave --fixed-fps or HSL_TEST_FIXED_FPS=0. On the real clock each
# headless frame sleeps and animations wait wall seconds: the 128-battle autoplay sweep took
# 2482–2770 s that way against 671–721 s under --fixed-fps, with the same results.
if [[ " $* " == *" --script res://tests/"* && " $* " != *" --fixed-fps "* && "${HSL_TEST_FIXED_FPS:-60}" != 0 ]]; then
  fast_clock="$(sed -n '/^FAST_CLOCK_SUITES = {/,/^}/p' "$ROOT/tools/verify_runner.py" | grep -o '"run_[a-z0-9_]*\.gd"' | tr -d '"' || true)"
  if sed -n '/^FAST_CLOCK_SUITES = {/,/^}/p' "$ROOT/tools/verify_runner.py" | grep -q '^ *SWEEP_SUITE,'; then
    fast_clock+=$'\n'"$(sed -n 's/^SWEEP_SUITE = "\(.*\)"$/\1/p' "$ROOT/tools/verify_runner.py")"
  fi
  for ((i = 1; i < $#; i++)); do
    if [[ "${!i}" == --script ]]; then
      j=$((i + 1))
      target="${!j#res://tests/}"
      if grep -qxF -- "$target" <<< "$fast_clock"; then
        set -- --fixed-fps "${HSL_TEST_FIXED_FPS:-60}" "$@"
        echo "tools/godot.sh: $target is a fast-clock suite; running with --fixed-fps $2 (HSL_TEST_FIXED_FPS=0 for the real clock)" >&2
      fi
      break
    fi
  done
fi

# Headless runs (imports, suites, sweeps) get an isolated HOME under ignored/ so they never read or
# overwrite the real user directory (campaign_progress.json, memoirs, settings). A 2026-09-27 suite
# run in the real HOME rewrote a real campaign save. HSL_REAL_HOME=1 opts out (tools/play.sh sets it).
if [[ " $* " == *" --headless "* && "${HSL_REAL_HOME:-}" != 1 && "${HOME:-}" != "$ROOT/ignored/"* ]]; then
  export HOME="$ROOT/ignored/lane-home"
  mkdir -p "$HOME"
fi

# Git ignore rules do not stop Godot importing raw captures. Prepare this before
# every entry, including the first play in a checkout that has never run verify.
mkdir -p "$ROOT/ignored"
if [[ ! -e "$ROOT/ignored/.gdignore" && ! -L "$ROOT/ignored/.gdignore" ]]; then
  printf '%s\n' '# Local capture output; not a Godot resource input.' > "$ROOT/ignored/.gdignore"
fi

# A checkout without an import cache (new lane worktree, fresh clone) seeds it from the worktree
# that imported most recently, so its first --import reconciles what differs instead of
# importing ~16k images from scratch. HSL_GODOT_SEED=0 keeps it cold (verify.sh --full).
if [[ ! -d "$ROOT/.godot/imported" && "${HSL_GODOT_SEED:-}" != 0 && -x "$ROOT/tools/godot_cache_seed.sh" ]]; then
  "$ROOT/tools/godot_cache_seed.sh" --auto "$ROOT" || echo "tools/godot.sh: cache seed failed; importing cold" >&2
fi

# --import is skipped when nothing Godot imports changed since the last successful one (stamps in
# .godot/hsl-import: start = when it began, end = when it finished, state = the scanned file list
# and class_name lines at start; a failed import leaves no end). It runs when a file of a kind Godot
# imports (every kind except those it reads directly: scripts, scenes, JSON, text) changed after
# start, or a *.import／*.uid after end (import writes these itself); when a file was added, removed
# or renamed (new scripts need their .uid); or when a class_name line changed (global class cache).
# "Changed" is ctime, so files synced in with an old mtime still count. Scanned like Godot's scan:
# hidden entries, __pycache__ and directories holding .gdignore are skipped. HSL_FORCE_IMPORT=1
# imports anyway.
stamps="$ROOT/.godot/hsl-import"
prune=()
scan_prune() {
  local g base=(-name '.?*' -o -name __pycache__)
  prune=("${base[@]}")
  while IFS= read -r g; do prune+=(-o -path "${g%/.gdignore}"); done \
    < <(cd "$ROOT" && find . -type d \( "${base[@]}" \) -prune -o -name .gdignore -print)
}
scan_state() {
  local files
  files="$(cd "$ROOT" && find . \( "${prune[@]}" \) -prune -o -type f ! -name '*.import' ! -name '*.uid' -print | LC_ALL=C sort)"
  printf '%s\n' "$files"
  printf '%s\n' "$files" | grep '\.gd$' | tr '\n' '\0' | (cd "$ROOT" && xargs -0 grep -HE '^class_name[[:space:]]') || true
}
import_needed() {  # prints why and returns 0 when an import is needed
  if [[ ! -d "$ROOT/.godot/imported" || ! -f "$stamps/start" || ! -f "$stamps/end" || ! -f "$stamps/state" ]]; then
    echo "no successful import recorded"; return 0
  fi
  local hit by_import=(-name '*.import' -o -name '*.uid')
  local direct=(-name '*.gd' -o -name '*.tscn' -o -name '*.tres' -o -name '*.gdshader' -o -iname '*.json'
    -o -iname '*.md' -o -iname '*.txt' -o -iname '*.h' -o -iname '*.tsv' -o -iname '*.sav' -o -name '*.obs')
  hit="$(cd "$ROOT" && find . \( "${prune[@]}" \) -prune -o -type f -newercm "$stamps/start" \
    \( \( "${by_import[@]}" \) -newercm "$stamps/end" -o ! \( "${by_import[@]}" \) ! \( "${direct[@]}" \) \) -print -quit)"
  if [[ -n "$hit" ]]; then echo "${hit#./} changed since the last import"; return 0; fi
  if ! scan_state | cmp -s - "$stamps/state"; then
    echo "files added, removed or renamed, or a class_name line changed, since the last import"; return 0
  fi
  return 1
}

# A rule suite (`extends "res://tests/support/TestSuite.gd"`) is not a MainLoop: Godot 4.7
# idles forever when given one through --script. Route it through the in-process runner:
# `--script res://tests/run_x_tests.gd` runs as `--script res://tests/run_all.gd -- run_x_tests.gd`
# (same PASS line and check count as in the batch).
args=("$@")
suite=""
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[i]}" == --script ]]; then
    target="${args[i + 1]:-}"
    if [[ "$target" == res://tests/run_*.gd && "$(head -n 1 "$ROOT/${target#res://}" 2>/dev/null)" == 'extends "res://tests/support/TestSuite.gd"' ]]; then
      suite="${target#res://tests/}"
      args[i + 1]="res://tests/run_all.gd"
    fi
  fi
done
if [[ -n "$suite" ]]; then
  echo "tools/godot.sh: $suite is an in-process rule suite; running it as --script res://tests/run_all.gd -- $suite" >&2
  user_args=0
  for arg in "${args[@]}"; do
    [[ "$arg" == -- || "$arg" == ++ ]] && user_args=1
  done
  if [[ "$user_args" -eq 1 ]]; then
    echo "tools/godot.sh: a rule suite takes no user arguments; run tools/godot.sh --headless --script res://tests/run_all.gd -- $suite" >&2
    exit 2
  fi
  args+=(-- "$suite")
fi
set -- "${args[@]}"

importing=0
for arg in "$@"; do
  [[ "$arg" == --import ]] && importing=1
done
if [[ "$importing" -eq 1 ]]; then
  scan_prune
  if [[ "${HSL_FORCE_IMPORT:-}" != 1 ]] && ! reason="$(import_needed)"; then
    echo "GODOT_IMPORT_SKIPPED nothing Godot imports changed since the last successful import (HSL_FORCE_IMPORT=1 imports anyway)"
    exit 0
  fi
  echo "tools/godot.sh: importing: ${reason:-forced}" >&2
  mkdir -p "$stamps"
  rm -f -- "$stamps/end"
  touch "$stamps/begin"
  scan_state > "$stamps/state.begin"
fi

log="$(mktemp "${TMPDIR:-/tmp}/hsl-godot.XXXXXX")"
trap 'rm -f -- "$log"' EXIT
# Launched from a macOS app (Ghostty, Terminal) Godot inherits that app's bundle identifier and
# macOS files its window under the terminal in the Dock／Cmd-Tab; drop it so the game is its own app.
# A new script without its .uid sidecar means the import was skipped over it (2026-09-27 FXQUEUE): force one.
if [[ -z "${HSL_FORCE_IMPORT:-}" ]] && find "$ROOT/game" "$ROOT/tests" -name '*.gd' -newer "$ROOT/.godot/imported" 2>/dev/null | while read -r gd; do [[ -e "$gd.uid" ]] || { echo "$gd"; break; }; done | grep -q .; then
  export HSL_FORCE_IMPORT=1
fi
unset __CFBundleIdentifier
result=0
"$GODOT_BIN" --path "$ROOT" "$@" 2>&1 | tee "$log" || result=$?
if grep -Eq 'SCRIPT ERROR:|ERROR:|ObjectDB instances were leaked|resources still in use' "$log"; then
  echo "Godot diagnostics failed verification" >&2
  if [[ "$result" -eq 0 ]]; then
    result=1
  fi
fi
if [[ "$importing" -eq 1 && "$result" -eq 0 ]]; then
  mv -f -- "$stamps/begin" "$stamps/start"
  mv -f -- "$stamps/state.begin" "$stamps/state"
  touch "$stamps/end"
fi
exit "$result"
