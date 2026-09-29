#!/usr/bin/env bash
# Human playtest launcher. Plays the real game (tools/play.sh) in its own profile, so your
# normal saves are untouched, with the playtest kit's eight walk slots as the 回憶錄 slots.
# A slot name starts the game straight in that slot (HSL_SKIP_TITLE=1 runs the title's 戰場記錄
# at once); `title` stops at the title. Everything the game prints is kept in
# ${HSL_PLAYTEST_HOME:-~/hsl-playtest}/logs/ for the agent to read afterwards.
# usage: tools/playtest.sh              list the slots (docs/PLAYTEST.md says what to look at)
#        tools/playtest.sh <slot>       l053, r012, b044, ... (a walk slot's number 1..8 works too;
#                                       b<level> is every battle the chapter walk entered)
#        tools/playtest.sh title        the title screen (設定選項, 回憶錄)
# The kit comes from: python3 tools/hsl_playtest_kit.py generate --force-win (walk slots) and
# python3 tools/hsl_playtest_kit.py raw (raw slots).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAYTEST_HOME="${HSL_PLAYTEST_HOME:-$HOME/hsl-playtest}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SLOT="${1:-}"
if [[ -z "$SLOT" || "$SLOT" == -h || "$SLOT" == --help || "$SLOT" == list ]]; then
  HSL_PLAYTEST_HOME="$PLAYTEST_HOME" "$PYTHON_BIN" "$ROOT/tools/hsl_playtest_kit.py" list
  exit 0
fi
HSL_PLAYTEST_HOME="$PLAYTEST_HOME" "$PYTHON_BIN" "$ROOT/tools/hsl_playtest_kit.py" install --slot "$SLOT"
mkdir -p "$PLAYTEST_HOME/logs"
log="$PLAYTEST_HOME/logs/$(date +%Y%m%d-%H%M%S)-$SLOT.log"
if [[ "$SLOT" == title ]]; then
  unset HSL_SKIP_TITLE
  echo "停在标题；读档：点书（回憶錄）。日誌：$log"
else
  export HSL_SKIP_TITLE=1
  echo "直达 $SLOT；换关：战斗中按 Esc →「讀取回憶錄」。日誌：$log"
fi
HOME="$PLAYTEST_HOME/home" "$ROOT/tools/play.sh" 2>&1 | tee "$log"
