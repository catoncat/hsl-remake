#!/usr/bin/env bash
# Safe source-checkout launcher, including after verify.sh removes import caches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-$(command -v godot || true)}"
if [[ -z "$GODOT_BIN" || ! -x "$GODOT_BIN" ]]; then
  echo "Godot executable not found; set GODOT_BIN or install Godot." >&2
  exit 1
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
unset __CFBundleIdentifier  # see tools/godot.sh: keep the game window out of the terminal's Dock entry
exec "$GODOT_BIN" --path "$ROOT" "$@"
