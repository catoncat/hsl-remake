#!/usr/bin/env bash
# Play the ORIGINAL game from a generated 回憶錄 preset, for side-by-side comparison with the remake.
#
#   tools/play_original.sh            # level06_pre_battle (第 6 關 席達鎮, the remake playtest kit's level-6 party)
#   tools/play_original.sh PRESET     # any preset under content/generated/hsl/development/original_saves/
#   tools/play_original.sh --restore  # put back the 回憶錄 row 1 this script last replaced
#
# The preset goes into 回憶錄 row 1 (SAVES/HSL00.SAV). Whatever was there is copied first to
# ~/hsl-playtest/original-save-backups/<YYYYmmdd-HHMMSS>/ ; --restore copies the newest such backup back.
# The original also writes SAVES/HSL.CFG when it exits, so the backup records that file too (a copy, or
# HSL.CFG.absent when there was none) and --restore puts it back or moves the new one into the backup.
# Refuses while the original is running (it would overwrite the save you are playing).
# After launching, the game window is moved to the main display (desktop 100,60) when the Wine input
# helper is built: a window left on a disconnected or secondary display takes no mouse clicks.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export WINEPREFIX="${WINEPREFIX:-$HOME/.wine-hsl-original}"
SAVES="$WINEPREFIX/drive_c/hsl/SAVES"
BACKUPS="${HSL_ORIGINAL_BACKUPS:-$HOME/hsl-playtest/original-save-backups}"
SLOT_FILE="HSL00.SAV"
CFG_FILE="HSL.CFG"

if pgrep -f 'hsl01\.exe' >/dev/null 2>&1; then
  echo "原版正在运行：先退出游戏再执行（否则会覆盖你正在玩的存档）。" >&2
  exit 1
fi
if [[ ! -d "$SAVES" ]]; then
  echo "找不到原版存档目录：${SAVES}（WINEPREFIX=${WINEPREFIX}）" >&2
  exit 1
fi

if [[ "${1:-}" == "--restore" ]]; then
  # Only this script's own timestamped backups count; other folders under $BACKUPS are left alone.
  latest="$(find "$BACKUPS" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]' 2>/dev/null | sort | tail -n 1 || true)"
  if [[ -z "$latest" ]]; then
    echo "没有备份可恢复（${BACKUPS}）。" >&2
    exit 1
  fi
  if [[ -f "$latest/$SLOT_FILE" ]]; then
    cp "$latest/$SLOT_FILE" "$SAVES/$SLOT_FILE"
    echo "已恢复 $SAVES/$SLOT_FILE ← $latest/$SLOT_FILE"
  else
    rm -f "$SAVES/$SLOT_FILE"
    echo "备份时 回憶錄 第 1 行是空的：已删除 $SAVES/$SLOT_FILE"
  fi
  if [[ -f "$latest/$CFG_FILE" ]]; then
    cp "$latest/$CFG_FILE" "$SAVES/$CFG_FILE"
    echo "已恢复 $SAVES/$CFG_FILE ← $latest/$CFG_FILE"
  elif [[ -f "$latest/$CFG_FILE.absent" && -f "$SAVES/$CFG_FILE" ]]; then
    mv -f "$SAVES/$CFG_FILE" "$latest/$CFG_FILE-written-by-original"
    echo "装入前没有 ${CFG_FILE}：原版退出时新写的那份已移到 $latest/$CFG_FILE-written-by-original"
  fi
  exit 0
fi

preset="${1:-level06_pre_battle}"
source_save="$ROOT/content/generated/hsl/development/original_saves/$preset.SAV"
if [[ ! -f "$source_save" ]]; then
  echo "没有这个预设：$source_save" >&2
  exit 1
fi

if [[ -f "$SAVES/$SLOT_FILE" ]] && cmp -s "$source_save" "$SAVES/$SLOT_FILE"; then
  # Already installed (a second run): keep the earlier backup as the one --restore uses.
  echo "回憶錄 第 1 行已经是 ${preset}，不再备份。"
else
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BACKUPS/$stamp"
  if [[ -f "$SAVES/$SLOT_FILE" ]]; then
    cp "$SAVES/$SLOT_FILE" "$BACKUPS/$stamp/$SLOT_FILE"
  fi
  if [[ -f "$SAVES/$CFG_FILE" ]]; then
    cp "$SAVES/$CFG_FILE" "$BACKUPS/$stamp/$CFG_FILE"
  else
    : > "$BACKUPS/$stamp/$CFG_FILE.absent"
  fi
  echo "$preset" > "$BACKUPS/$stamp/installed_preset.txt"
  cp "$source_save" "$SAVES/$SLOT_FILE"
  echo "已装入 $preset → 回憶錄 第 1 行（原来的存档备份在 $BACKUPS/$stamp/）"
fi

case "$preset" in
  level06_pre_battle)
    cat <<'EOF'

进关步骤：
  1. 标题画面选「戰場記錄」（载入已有的战场记录即可，不用打）。
  2. 在战场上按 Esc 打开系统选单 →「讀取回憶錄」→ 选第 1 行（席達鎮 等級08 4:00）。
  3. 载入后先是 琥／雷歐納德 在席達鎮的几句对白（按空格或点左键翻页），然后出现城镇选单。
  4. 选「酒館」→ 侍女招呼后出现酒馆选单 → 选「沃斯菲塔士兵」，对话结束后直接开打第 6 关。
队伍与重制 playtest kit 第 6 关入口（memoir_05）相同：雷歐納德 8 级、緹娜 5 级（水剎）、琥 7 级、漢克斯 8 级（逆刃），装备与道具相同。
原版窗口保持在主显示器上；鼠标点击没反应时，把窗口拖回主显示器（或运行 python3 tools/hsl_original_control.py place 100 60）。
玩完后先退出原版，再恢复原来的存档：tools/play_original.sh --restore
EOF
    ;;
  *)
    echo "进关：标题「戰場記錄」→ 战场上按 Esc 打开系统选单 →「讀取回憶錄」→ 第 1 行。玩完后：tools/play_original.sh --restore"
    ;;
esac

"$ROOT/tools/run_original_hsl.sh"

# Move the window to the main display once it exists (best effort; needs ignored/bin/hsl_win32_control.exe).
if [[ -f "$ROOT/ignored/bin/hsl_win32_control.exe" ]]; then
  for _ in $(seq 1 20); do
    sleep 1
    if python3 "$ROOT/tools/hsl_original_control.py" place 100 60 >/dev/null 2>&1; then
      echo "原版窗口已放到主显示器 (100,60)。"
      exit 0
    fi
  done
  echo "没能自动放置原版窗口；若点击没反应，把窗口拖回主显示器。" >&2
else
  echo "（未构建 ignored/bin/hsl_win32_control.exe，跳过自动放置窗口：tools/build_runtime_helpers.sh --win32-control）"
fi
