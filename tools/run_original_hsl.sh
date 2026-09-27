#!/usr/bin/env bash
set -euo pipefail

WINE_BIN="${WINE_BIN:-/opt/homebrew/bin/wine}"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-hsl-original}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-ddraw=n,b;mscoree,mshtml=}"
export WINEDEBUG="${WINEDEBUG:--all}"
GAME_DIR_UNIX="${HSL_GAME_DIR_UNIX:-$WINEPREFIX/drive_c/hsl}"
GAME_DIR_WINDOWS="${HSL_GAME_DIR_WINDOWS:-C:\\hsl}"
GAME_EXE_WINDOWS="${HSL_GAME_EXE_WINDOWS:-C:\\hsl\\hsl01.exe}"

if [[ ! -x "$WINE_BIN" ]]; then
  echo "Wine binary not found or not executable: $WINE_BIN" >&2
  exit 1
fi

if [[ ! -f "$GAME_DIR_UNIX/hsl01.exe" ]]; then
  echo "Original HSL executable not found: $GAME_DIR_UNIX/hsl01.exe" >&2
  exit 1
fi

exec "$WINE_BIN" start /d "$GAME_DIR_WINDOWS" "$GAME_EXE_WINDOWS"
