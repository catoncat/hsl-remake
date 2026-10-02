#!/usr/bin/env bash
# Safe source-checkout launcher, including after verify.sh removes import caches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found; set GODOT_BIN or install Godot." >&2
  exit 1
fi
# A checkout without the original-derived files (the public repository ships none) imports them from the
# player's copy first (tools/hsl.py bootstrap, HSL_ORIGINAL_DIR); an interrupted import leaves its marker
# and resumes here. A complete checkout pays two file tests.
if [[ ! -f "$ROOT/content/imported/hsl/global/tables/PLAYERS.TXT" || -e "$ROOT/ignored/hsl-bootstrap/incomplete" ]]; then
  PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || echo python3)}"
  if ! "$PYTHON_BIN" "$ROOT/tools/hsl.py" bootstrap; then
    if [[ ! -f "$ROOT/content/imported/hsl/global/tables/PLAYERS.TXT" ]]; then
      echo "Original data not imported; refusing to open the game without it." >&2
      exit 1
    fi
    echo "Original-data import incomplete (tasks listed above); starting with what was imported." >&2
  fi
fi
# godot.sh seeds a missing import cache from another worktree and skips the import (about 0.3 s
# instead of a Godot scan of every file) when nothing it imports changed since the last success.
log="$(mktemp "${TMPDIR:-/tmp}/hsl-play-import.XXXXXX")"
trap 'rm -f -- "$log"' EXIT
export HSL_REAL_HOME=1  # playing uses the real user directory (saves, settings)
if ! GODOT_BIN="$GODOT_BIN" "$ROOT/tools/godot.sh" --headless --import > "$log" 2>&1; then
  cat "$log" >&2
  echo "Asset import failed; refusing to open an incomplete game window." >&2
  exit 1
fi
rm -f -- "$log"
trap - EXIT
# Development switch: P freezes the game and N steps one frame (game/debug/DebugPause.gd).
# On for every launch through here, playtests included; HSL_DEBUG_PAUSE=0 turns it off.
export HSL_DEBUG_PAUSE="${HSL_DEBUG_PAUSE:-1}"
# Product self-heal (game/sim/ProgressionRules.gd self_heal): an inconsistent derived profile is
# refreshed and logged as HSL_SELF_HEAL instead of stopping the battle. Tests and autoplay (which
# never come through here) stay strict; HSL_SELF_HEAL=0 turns it off here too.
export HSL_SELF_HEAL="${HSL_SELF_HEAL:-1}"
# Script-driven windows (the tests/capture_*.gd review drivers) reset campaign progress and other
# user:// files, so they get their own HOME under ignored/ and never delete the player's real saves.
case " $* " in
  *" --script "*|*" --script="*|*" -s "*)
    if [[ "${HOME:-}" != "$ROOT/ignored/"* ]]; then
      export HOME="$ROOT/ignored/script-home"
      mkdir -p "$HOME"
    fi ;;
esac
unset __CFBundleIdentifier  # see tools/godot.sh: keep the game window out of the terminal's Dock entry
exec "$GODOT_BIN" --path "$ROOT" "$@"
