# Level 60 story scene（王座廳・俘虜）runtime observation

> evidence: runtime-measured; provisional · status: live · tools: capture_story_scene_review.gd, hsltools/levels/actors.py, hsltools/levels/seed.py, run_story_scene_tests.gd · updated: 2026-09-18

- 采集日期：2026-09-18；分支 presentation-line；Godot 4.7.2 可见窗口 640×480（`tools/play.sh --screen 0 --script res://tests/capture_story_scene_review.gd -- --level=60`），正常重制节奏。
- 证据等级：**runtime-measured**（重制版自身行为）；对原作的关系全部 **provisional**。
- 完整原始输出（23 张 PNG＋manifest.json）留在 `ignored/story-scene-060-review/`；本包提升 6 帧。

## 来源与数据链（resource-derived）

- PAK 有 `STORY060.TXT`、`level060.BIN/.wrd`、`obj-060.obs`，无 `winfail060`（story-only）、无 `obj-060.h`（脚本 `#include OBJ-058.H`，seed 按 include 借用）、无 `level60.shp`；`level060.wrd` 与 `level058.wrd` 字节相同，因此 `tools/hsltools/levels/seed.py` 以 `MAP_ALIASES={60: 58}` 复用王座厅地图（引擎 level→map 表未定位，alias 标 provisional）。
- EVEF 15 个角色：058 克里歐司、027×2、024×8、023×3（一般兵）、029；无 player_install，Leonard 不在场。`PLAYERS.TXT` 角色 29 的 name 字段为符号 `name_1` → `resource.h` 1 → RESOURCE.TXT「緹娜」；`tools/hsltools/levels/actors.py` 现解析 `name_N` 符号。
- 对白 676–692 加复用的 380/678；`STORY060` 新 token `actWalkAndDeleteWait` 编入 `actor_walk_and_delete_wait`；43 事件（42 token＋`scene_end_marker`），checker profile `story060`。`actSetNextPlayLevelEvent(53,53)` 指向 winfail053 战斗关。

## 观察到的结果

1. `story_060.json`（`player_unit_id: null`）经 `level_kind: story` 分支启动，无 PlayLoop；镜头对准王座（`00-throne-framed`）。
2. 一般兵 023_1 从 (384,800) 走到 (288,384) 报告（`walk-it-sid_enemy023`，676），返回后带俘虏 029 缇娜与两名护卫 023_2/023_3 以 `actWalkFollow(Wait)` 上前（`escort-follows`）；缇娜以 PLAYERS 名与 FACE0029 肖像说话（`dialogue-683`）。
3. 20 个 message token 全部分页，无跳过；两名护卫 `actWalkAndDelete(Wait)` 先退场，随后 023_1 与缇娜退场（4 条 `actor_deleted`）。
4. `actPlayMusic,8` 复用原创《沃斯菲塔王座廳》；`[53,53]` 无场景 → 章末卡「level 53 尚未重製」（`chapter-end-card`）。总时长 25.3 s。
5. level 58 结束时 `[60,60]` 现经 `CampaignProgress.start_story_handoff` 直接进入本场景并落盘位置（headless 覆盖于 `tests/run_story_scene_tests.gd`）。

## 边界（不支持的结论）

- 地图 alias、走位速度、跟随偏移、删除时机为重制取值；`一般兵`/`???` 标签沿用 level 51 重制标签，非 PLAYERS 姓名。
- level 53（winfail053 战斗）尚未重制，战役在此止于章末卡。
