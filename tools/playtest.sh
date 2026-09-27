#!/usr/bin/env bash
# Human playtest launcher. Plays the real game (tools/play.sh) in its own profile, so your
# normal saves are untouched, with the playtest kit's eight 回憶錄 slots installed; the
# title screen's 戰場記錄 goes straight into slot N. Everything the game prints is kept in
# ${HSL_PLAYTEST_HOME:-~/hsl-playtest}/logs/ for the agent to read afterwards.
# usage: tools/playtest.sh [N]        N = kit slot 1..8 (default 1); docs/PLAYTEST.md lists them
# The kit itself comes from: python3 tools/hsl_playtest_kit.py generate
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAYTEST_HOME="${HSL_PLAYTEST_HOME:-$HOME/hsl-playtest}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SLOT="${1:-1}"
HSL_PLAYTEST_HOME="$PLAYTEST_HOME" "$PYTHON_BIN" "$ROOT/tools/hsl_playtest_kit.py" install --slot "$SLOT"
mkdir -p "$PLAYTEST_HOME/logs"
log="$PLAYTEST_HOME/logs/$(date +%Y%m%d-%H%M%S)-slot$SLOT.log"
echo "標題選「戰場記錄」進入驗收 ${SLOT}；其他驗收關：戰鬥中按 Esc →「讀取回憶錄」。日誌：$log"
HOME="$PLAYTEST_HOME/home" "$ROOT/tools/play.sh" 2>&1 | tee "$log"
