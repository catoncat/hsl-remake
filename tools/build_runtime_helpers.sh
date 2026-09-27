#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTC_BIN="${SWIFTC_BIN:-$(command -v swiftc || true)}"
MINGW32_BIN="${MINGW32_BIN:-$(command -v i686-w64-mingw32-gcc || true)}"
BUILD_WIN32_RPM=0
BUILD_WIN32_CONTROL=0

usage() {
  cat <<'EOF'
usage: tools/build_runtime_helpers.sh [--win32-rpm|--win32-control]

Build the two native macOS window/input helpers. Pass --win32-rpm only when
the optional Wine scalar-memory probe helper is also needed.
--win32-control builds only the Win32 input/surface-screenshot trigger helper.
EOF
}

case $# in
  0) ;;
  1)
    case "$1" in
      --win32-rpm) BUILD_WIN32_RPM=1 ;;
      --win32-control) BUILD_WIN32_CONTROL=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 2 ;;
    esac
    ;;
  *) usage >&2; exit 2 ;;
esac

if [[ "$BUILD_WIN32_CONTROL" -eq 0 && -z "$SWIFTC_BIN" ]]; then
  echo "swiftc not found; install the Xcode Command Line Tools" >&2
  exit 1
fi

build_one() {
  local source="$1"
  local output="$2"
  shift 2
  local temp="${output}.tmp.$$"
  trap 'rm -f "$temp"' RETURN
  "$SWIFTC_BIN" -O -o "$temp" "$source" "$@"
  chmod +x "$temp"
  mv "$temp" "$output"
  trap - RETURN
  file "$output"
}

if [[ "$BUILD_WIN32_CONTROL" -eq 0 ]]; then
  build_one "$SCRIPT_DIR/hsl_window.swift" "$SCRIPT_DIR/hsl_window" -framework CoreGraphics
  build_one "$SCRIPT_DIR/hsl_input.swift" "$SCRIPT_DIR/hsl_input" -framework AppKit -framework ApplicationServices
fi

if [[ "$BUILD_WIN32_CONTROL" -eq 1 ]]; then
  if [[ -z "$MINGW32_BIN" ]]; then
    echo "i686-w64-mingw32-gcc not found; cannot build win32 control helper" >&2
    exit 1
  fi
  mkdir -p "$PROJECT_DIR/ignored/bin"
  OUTPUT="$PROJECT_DIR/ignored/bin/hsl_win32_control.exe"
  TEMP="${OUTPUT}.tmp.$$"
  trap 'rm -f "$TEMP"' EXIT
  "$MINGW32_BIN" -std=c11 -O2 -Wall -Wextra -Werror -o "$TEMP" "$SCRIPT_DIR/hsl_win32_control.c" -luser32
  mv "$TEMP" "$OUTPUT"
  trap - EXIT
  file "$OUTPUT"
  exit 0
fi

if [[ "$BUILD_WIN32_RPM" -eq 1 ]]; then
  if [[ -z "$MINGW32_BIN" ]]; then
    echo "i686-w64-mingw32-gcc not found; cannot build the requested win32-rpm helper" >&2
    exit 1
  fi
  mkdir -p "$PROJECT_DIR/ignored/bin"
  WIN32_OUTPUT="$PROJECT_DIR/ignored/bin/hsl_win32_memread.exe"
  WIN32_TEMP="${WIN32_OUTPUT}.tmp.$$"
  trap 'rm -f "$WIN32_TEMP"' EXIT
  "$MINGW32_BIN" -O2 -Wall -Wextra -o "$WIN32_TEMP" "$SCRIPT_DIR/hsl_win32_memread.c"
  mv "$WIN32_TEMP" "$WIN32_OUTPUT"
  trap - EXIT
  file "$WIN32_OUTPUT"
fi

echo "native runtime helpers built under $SCRIPT_DIR"
if [[ "$BUILD_WIN32_RPM" -eq 1 ]]; then
  echo "optional win32-rpm helper built under $PROJECT_DIR/ignored/bin"
fi
